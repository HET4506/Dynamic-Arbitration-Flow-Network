# DFAN --- Dynamic Flow Arbitration Network

## Design Flow and Constraint Analysis

**Source:** `IAE_DAU_Tech_Day_VLSI_Problem_Statements_V1.0.pdf`\
**Module:** `DFAN_Controller`\
**Target:** Synthesizable Verilog HDL / FPGA implementation

------------------------------------------------------------------------

## 1. Problem Overview

DFAN (Dynamic Flow Arbitration Network) is a hardware scheduler for four
independent flow domains:

-   `N0`
-   `N1`
-   `N2`
-   `N3`

The controller regulates access to a shared transition zone under:

-   dynamic demand,
-   priority override requests,
-   an asynchronous global pause request,
-   compatibility/exclusion constraints,
-   temporal ownership-transfer rules,
-   adaptive allocation history,
-   and fault conditions.

The PDF specifies the DFAN inputs as:

-   `clk`
-   `rst_n`
-   `demand_N0` ... `demand_N3`, each ranging from 0 to 15
-   `por_N0` ... `por_N3`
-   `px_request`

The outputs include:

-   `state_N0` ... `state_N3`
-   `px_grant`
-   `fault_flag`

The four domain states are:

  Encoding   State
  ---------- --------------
  `00`       Blocked
  `01`       Transitional
  `10`       Active
  `11`       Reserved

The PDF also requires the design to be synthesizable, parameterizable,
deterministic, deadlock-free, starvation-free, and suitable for FPGA
implementation.

------------------------------------------------------------------------

# 2. Overall Design Philosophy

We are separating DFAN into two major ideas:

1.  **Decision logic** --- determines which domain(s) should be
    candidates for allocation.
2.  **FSM/state-control logic** --- determines whether that candidate
    can legally become active and controls ownership transitions.

The scheduler should not be a single large comparison statement. Each
constraint contributes a specific piece of the decision.

The current conceptual order is:

``` text
PX / Global Pause
        |
        v
Priority Override
        |
        v
Normal Demand + Fairness Score
        |
        v
Compatibility Check
        |
        v
Temporal / FSM Legality
        |
        v
Final Allocation
```

PX is treated separately because the PDF explicitly defines it as an
asynchronous Global Pause Agent rather than a normal scheduler
participant.

------------------------------------------------------------------------

# 3. Constraint A --- Compatibility Matrix

## Requirement from the PDF

The compatibility rules are:

-   `N0 + N1` may be active simultaneously.
-   `N2 + N3` may be active simultaneously.
-   Every other combination is incompatible and must never occur.

## Our interpretation

We divide the four domains into two compatible pairs:

``` text
Pair 0:  N0 <----> N1

Pair 1:  N2 <----> N3
```

Therefore:

``` text
N0 + N1  -> ALLOWED
N2 + N3  -> ALLOWED

N0 + N2  -> FORBIDDEN
N0 + N3  -> FORBIDDEN
N1 + N2  -> FORBIDDEN
N1 + N3  -> FORBIDDEN
```

A domain with zero demand is not a candidate for allocation.

For a compatible pair, if both domains have non-zero demand, they are
eligible to coexist. If only one has demand, that domain becomes the
candidate from that pair.

### Important

Compatibility is a **hard constraint**, not merely a scheduling
preference. The scheduler may choose candidates using demand/fairness,
but the final allocation must always obey the compatibility matrix.

------------------------------------------------------------------------

# 4. Constraint B --- Demand-Weighted Allocation

## Requirement from the PDF

The PDF requires:

-   allocation duration to be proportional to demand,
-   the highest-demand domain must not monopolize the system,
-   the lowest-demand domain must eventually receive service,
-   aggregate throughput should be maximized,
-   the scheduler must remain starvation-free.

## Initial idea

A simple comparator that always selects:

``` text
highest demand -> allocation
```

is insufficient.

Example:

``` text
N0 = 15
N1 = 5
N2 = 3
N3 = 2
```

If N0 continuously remains the highest-demand requester, a pure
maximum-demand scheduler could keep selecting N0.

That violates the anti-monopoly and starvation requirements.

## Fairness mechanism

We introduced a waiting counter:

\[ W_i = `\text{number of cycles domain }`{=tex} N_i
`\text{ has waited for service}`{=tex} \]

and a demand/fairness score:

\[ S_i = D_i `\times `{=tex}W_i \]

where:

-   (D_i) = current demand
-   (W_i) = waiting cycles

Thus, waiting increases the influence of a domain's demand.

A domain with moderate demand can eventually become a stronger candidate
if it has waited long enough.

A domain with zero demand remains irrelevant:

\[ D_i=0 `\Rightarrow `{=tex}S_i=0 \]

This avoids generating artificial service demand.

------------------------------------------------------------------------

## Active-cycle tracking

We distinguish between:

\[ W_i = `\text{waiting cycles}`{=tex} \]

and

\[ A_i = `\text{active cycles}`{=tex} \]

`W_i` is used for fairness.

`A_i` records how long a domain has occupied the resource during its
current/previous allocation.

These counters should not be treated as the same quantity.

------------------------------------------------------------------------

# 5. Constraint C --- Temporal Integrity

## Requirement from the PDF

The PDF requires:

-   a domain that loses ownership cannot immediately regain ownership,
-   a mandatory Transitional phase must exist between ownership
    transfers,
-   no ownership transfer may bypass Transitional.

## Our solution

Ownership changes are controlled through the FSM:

``` text
ACTIVE
  |
  | allocation ends
  v
TRANSITIONAL
  |
  | minimum transition interval
  v
NEXT ACTIVE
```

A direct transfer such as:

``` text
N0 ACTIVE -> N1 ACTIVE
```

is illegal.

The legal sequence is:

``` text
N0 ACTIVE
     |
     v
TRANSITIONAL
     |
     v
N1 ACTIVE
```

A minimum transition-cycle counter is retained so that the transition
phase cannot be skipped or made arbitrarily short.

The recently served domain is also prevented from immediately regaining
ownership through the scheduler's fairness/history mechanism.

------------------------------------------------------------------------

# 6. Constraint D --- Priority Override

## Requirement from the PDF

Priority Override has three requirements:

1.  Current allocation may not be instantly revoked.
2.  Priority requests must be acknowledged within bounded latency.
3.  Simultaneous priority requests must be resolved deterministically.

## Our scheduling hierarchy

Priority Override is checked before normal demand-based scheduling.

Conceptually:

``` text
Priority request?
       |
   +---+---+
   |       |
  YES      NO
   |       |
   v       v
Priority  Normal
candidate scheduler
```

However, priority does not bypass temporal integrity.

If `N1` is currently active and `N0` asserts priority:

``` text
N1 ACTIVE
    |
    v
TRANSITIONAL
    |
    v
N0 ACTIVE
```

not:

``` text
N1 ACTIVE -> N0 ACTIVE
```

For simultaneous priority requests, the controller must use a
deterministic tie-breaking rule. The PDF requires deterministic
resolution but does not specify the exact tie-break mechanism, so the
final rule must be explicitly defined in the design.

------------------------------------------------------------------------

# 7. Constraint E --- Global Pause Agent (PX)

## Requirement from the PDF

The PDF defines PX as a Global Pause Agent:

-   PX does not participate in normal scheduling.
-   No domain may remain active while PX is being serviced.
-   PX requests are asynchronous and must not starve.

## Our interpretation

PX has global authority over normal domain operation.

When an asynchronous PX request is asserted:

``` text
PX_REQUEST
     |
     v
GLOBAL PAUSE
     |
     +--> N0 inactive
     +--> N1 inactive
     +--> N2 inactive
     +--> N3 inactive
```

PX therefore bypasses normal demand and priority arbitration.

### Important distinction

PX being asynchronous means the pause request does not have to wait for
a normal scheduling decision before asserting the global pause
condition.

It does not automatically mean that the FPGA's physical clock must be
shut off.

The intended behavior is to asynchronously force the normal domain
operation into a safe paused condition while the control circuitry
remains capable of handling PX and returning to normal operation.

`px_grant` indicates that PX is being serviced.

------------------------------------------------------------------------

# 8. Constraint F --- Adaptive Behavior / Allocation History

## Requirement from the PDF

The PDF requires:

-   a rolling history of recent allocations,
-   historical activity must influence future allocation decisions.

## History storage

We currently plan to use a **10-entry rolling allocation history**.

Conceptually:

``` text
H[0] = newest allocation
H[1] = previous allocation
H[2]
...
H[9] = oldest retained allocation
```

Example:

``` text
[N0, N2, N1, N0, N3, N2, N1, N0, N2, N3]
```

From this history we can calculate how frequently each domain appeared.

Define:

\[ H_i =
`\text{number of recent history entries belonging to }`{=tex}N_i \]

For a 10-entry history:

\[ 0 `\le `{=tex}H_i `\le 10`{=tex} \]

and, assuming every entry represents one domain allocation:

\[ H_0+H_1+H_2+H_3=10 \]

------------------------------------------------------------------------

## History must affect scheduling

Simply storing the history is not enough.

The history is fed back into the future allocation decision.

We therefore separate:

``` text
Current demand
       |
Waiting history
       |
Recent allocation history
       |
       v
Fairness / Scheduling score
       |
       v
Candidate selection
```

------------------------------------------------------------------------

## Dynamic history penalty

To avoid fractional arithmetic such as:

\[ `\frac{1}{1+H_i}`{=tex} \]

we use an integer-based history penalty.

Our current candidate equation is:

\[ `\boxed{
S_i = D_i W_i - L_i H_i
}`{=tex} \]

where:

-   (D_i) = current demand
-   (W_i) = waiting cycles
-   (H_i) = number of times (N_i) appeared in the recent allocation
    history
-   (L_i) = duration of (N_i)'s previous allocation

Thus:

\[ L_i = `\text{last active allocation duration of }`{=tex}N_i \]

This makes the history penalty dynamic.

If a domain previously occupied the resource for a long time, its recent
history has a stronger effect on the next scheduling decision.

Example:

\[ D_0=12,`\quad `{=tex}W_0=5,`\quad `{=tex}H_0=3,`\quad `{=tex}L_0=6 \]

Then:

\[ S_0=(12)(5)-(6)(3)=42 \]

This is an integer-only calculation suitable for RTL.

### Status of this equation

This is our **current proposed mathematical model**, not an equation
mandated by the PDF. The PDF only requires demand-weighted behavior,
fairness, starvation freedom, and historical influence. The exact
scoring equation must be validated through simulation.

------------------------------------------------------------------------

# 9. Constraint G --- Fault Handling

## Requirement from the PDF

The output `fault_flag` indicates illegal, conflicting, or unrecoverable
conditions.

The fault-handling section identifies conditions including:

-   multiple Priority Overrides,
-   demand overflow,
-   reset during transition,
-   illegal state entry,
-   history corruption,
-   invalid scheduling decision.

## Fault architecture

Fault detection is treated as a separate safety layer around the
scheduler/FSM.

Conceptually:

``` text
                  +----------------+
Inputs ---------->| Scheduler/FSM  |------> Outputs
                  +----------------+
                           |
                           v
                    Fault Checker
                           |
                           v
                      fault_flag
```

Examples of conditions that should be detected include:

### Illegal coexistence

Any active combination outside:

``` text
N0 + N1
N2 + N3
```

must trigger fault handling.

### Transition violation

A direct ownership transfer that bypasses Transitional is an illegal
condition.

### PX violation

If PX is being serviced while a normal domain remains active, the
condition conflicts with Constraint E.

### Invalid scheduling decision

If the decision logic produces an allocation that cannot be reconciled
with the compatibility/state rules, `fault_flag` must be asserted.

### History corruption

The history structure should be checked for impossible/inconsistent
values according to the implemented history representation.

------------------------------------------------------------------------

# 10. Current Internal Data Model

The current conceptual state/data elements are:

``` text
Demand:
D0 D1 D2 D3

Waiting counters:
W0 W1 W2 W3

Active-cycle counters:
A0 A1 A2 A3

Previous allocation duration:
L0 L1 L2 L3

10-entry allocation history:
H[0:9]

History counts:
H0 H1 H2 H3

Priority:
POR0 POR1 POR2 POR3

Global pause:
PX_REQUEST

FSM:
Blocked
Transitional
Active
Reserved

Outputs:
state_N0
state_N1
state_N2
state_N3
px_grant
fault_flag
```

------------------------------------------------------------------------

# 11. Decision Hierarchy

The current design reasoning is:

## Level 1 --- Global PX

``` text
PX request?
    |
   YES
    |
    v
Global pause
```

PX is asynchronous and has global authority.

## Level 2 --- Priority Override

If PX is not being serviced:

``` text
Priority request?
    |
   YES
    |
    v
Priority candidate
```

Priority cannot bypass Transitional.

## Level 3 --- Normal demand/fairness scheduler

If there is no priority request:

\[ S_i=D_iW_i-L_iH_i \]

Calculate the score for each requesting domain.

## Level 4 --- Compatibility

Check whether the selected candidate can coexist with another
requested/active domain.

Allowed:

``` text
N0 + N1
N2 + N3
```

## Level 5 --- Temporal legality / FSM

Check:

-   current state,
-   Transitional requirement,
-   transition timing,
-   re-entry restriction,
-   PX state,
-   reset/fault conditions.

## Level 6 --- Final allocation

Only after all required conditions are satisfied is the next
state/output committed.

------------------------------------------------------------------------

# 12. Overall Block Diagram

``` text
                           +----------------------+
                           |     FPGA Inputs      |
                           |----------------------|
                           | clk / rst_n          |
                           | demand_N0..N3        |
                           | por_N0..N3           |
                           | PX_REQUEST           |
                           +----------+-----------+
                                      |
                                      v
                    +----------------------------------+
                    |        INPUT / CONTROL LOGIC     |
                    +----------------+-----------------+
                                     |
                 +-------------------+-------------------+
                 |                                       |
                 v                                       v
       +-------------------+                    +-------------------+
       |  PX ASYNC CONTROL |                    | PRIORITY LOGIC    |
       |  Global Pause     |                    | POR Arbitration   |
       +---------+---------+                    +---------+---------+
                 |                                        |
                 |                                        |
                 +-------------------+--------------------+
                                     |
                                     v
                         +-------------------------+
                         | DEMAND / FAIRNESS LOGIC|
                         |-------------------------|
                         | D x W                  |
                         | History counts         |
                         | Last allocation time   |
                         | S = D*W - L*H          |
                         +------------+------------+
                                      |
                                      v
                         +-------------------------+
                         |   CANDIDATE SELECTOR    |
                         |   Comparators            |
                         +------------+------------+
                                      |
                                      v
                         +-------------------------+
                         | COMPATIBILITY CHECK     |
                         | N0+N1 / N2+N3 only      |
                         +------------+------------+
                                      |
                                      v
                         +-------------------------+
                         |      DFAN FSM            |
                         |-------------------------|
                         | Blocked                  |
                         | Transitional            |
                         | Active                   |
                         | Reserved                 |
                         +------------+------------+
                                      |
                    +-----------------+------------------+
                    |                                    |
                    v                                    v
          +----------------------+             +----------------------+
          | OUTPUT STATE REGISTERS|             | FAULT CHECKER        |
          | state_N0..state_N3    |             | illegal coexistence  |
          | px_grant              |             | invalid state        |
          | fault_flag            |             | PX violation         |
          +----------------------+             | invalid decision     |
                                               +----------------------+
                    ^
                    |
          +---------+----------+
          | 10-ENTRY HISTORY   |
          | Allocation history |
          +--------------------+
                    |
                    +----> feeds fairness logic
```

------------------------------------------------------------------------

# 13. Pipeline / Decision Workflow

The controller's logical workflow is:

``` text
        START / RESET
              |
              v
       Read current inputs
              |
              v
       Is PX requested?
          /         \
        YES          NO
         |            |
         v            v
   Global Pause   Check POR
                      |
                 +----+----+
                YES        NO
                 |          |
                 v          v
          Priority      Calculate
          candidate     normal scores
                            |
                            v
                   S_i = D_iW_i - L_iH_i
                            |
                            v
                    Compare candidates
                            |
                            v
                    Select candidate
                            |
                            v
                    Check compatibility
                            |
                            v
                  Ownership changing?
                       /          \
                     NO            YES
                     |              |
                     v              v
                Continue       Transitional
                                    |
                                    v
                          Minimum transition time
                                    |
                                    v
                             New allocation
                                    |
                                    v
                         Update active cycles
                                    |
                                    v
                          Update waiting counters
                                    |
                                    v
                        Update 10-entry history
                                    |
                                    v
                         Update last duration L
                                    |
                                    v
                          Fault validation
                                    |
                                    v
                           Output registers
                                    |
                                    v
                              Next cycle
```

------------------------------------------------------------------------

# 14. What Is Still Not Finalized

Before RTL implementation, the following items should be mathematically
fixed and verified:

1.  Exact update rules for `W_i`.
2.  Exact update rules for `L_i`.
3.  Exact interpretation of simultaneous `N0+N1` / `N2+N3` allocations.
4.  Deterministic tie-breaking for equal normal scores.
5.  Deterministic tie-breaking for simultaneous Priority Overrides.
6.  Exact minimum Transitional duration.
7.  Exact bounded-latency requirement for Priority Override.
8.  Exact asynchronous implementation behavior for PX.
9.  Exact fault response after `fault_flag`.
10. Verification of the proposed score:

\[ S_i=D_iW_i-L_iH_i \]

against starvation, throughput, demand proportionality, and edge cases.
11. Widths required for all counters and intermediate arithmetic. 12.
Behavior during reset, including reset during Transitional.

These should be resolved **before writing the main Verilog**, so the RTL
becomes an implementation of an already-defined mathematical/behavioral
model rather than the place where the specification is invented.

------------------------------------------------------------------------

# 15. Design Status

### Conceptually established

-   FSM-based architecture
-   Compatibility groups
-   Demand-based candidate selection
-   Waiting-based fairness
-   Mandatory Transitional phase
-   Priority Override hierarchy
-   Asynchronous PX global pause
-   10-entry rolling allocation history
-   History feedback into scheduling
-   Fault-checking layer
-   FPGA-oriented synchronous implementation for normal control

### Current proposed core equation

\[ `\boxed{
S_i=D_iW_i-L_iH_i
}`{=tex} \]

### Current proposed history

\[ `\boxed{
HISTORY[0:9]
}`{=tex} \]

### Current next step

**Do not begin full RTL yet.**

First mathematically define the update equations and state-transition
table for the FSM, then test those rules against representative cases.
After that, map each equation/block into synthesizable Verilog.
