## Core Concepts – Suflex Activation Health Score

### Unified activation journey

- **Single activation funnel**: Setup and value are modeled as a **single continuous journey**, not two separate scores.
- **Setup as prerequisite**: Setup actions are necessary but not sufficient; true activation is only achieved when the user captures real value.
- **Time-to-Value Window (TTVW)**: All activation behavior is evaluated in a fixed window, currently **30 days** from the restaurant’s onboarding start (e.g. `restaurants.inserted_at` or agreed activation start date).

### User / account activation

- **Grain**: Activation is primarily evaluated **per restaurant (account)**, aggregating actions by all relevant users/employees in that restaurant.
- **Activated (business definition)**: A restaurant is considered **Activated** at the end of the TTVW if:
  - It accumulates a **Total Activation Score ≥ 80 points** (Lock), **and**
  - It performs at least one **core value action** (Key) involving **controlled products with weight** (e.g. weighted count, weighted write-off, or weighted receiving).

### User roles used in metrics

- **restaurant_admin** – used as the **manager/gestor** role for activation metrics.
- **restaurant_employee** – used as the **collaborator** role for activation metrics.


### Activation health score

- **Scale**: Numeric **0–100** health score focused on early activation.
- **Components (psychological buckets)**:
  - **Setup (max 10 pts)** – basic exploration and configuration:
    - ≥ 1 login gestor (1 pt).
    - ≥ 1 login colaborador (1 pt).
    - ≥ 2 listas de contagem criadas com ≥ 1 produto controlado cada (3 pts).
    - ≥ 5 produtos controlados cadastrados com peso (5 pts).
  - **Effort & Commitment (max 30 pts)** – heavier configuration and repeated usage:
    - 50 impressões realizadas (3 pts).
    - 30 impressões de produtos controlados (7 pts).
    - 10 baixas realizadas (15 pts).
    - 5 contagens (5 pts).
  - **Value Capture (max 60 pts)** – closing the loop on financial ROI:
    - 20 impressões com peso (15 pts).
    - 30 impressões de produtos controlados com peso (10 pts).
    - 5 baixas de etiquetas de produtos controlados com peso (25 pts).
    - 2 contagens com ≥ 1 produto controlado cada, com peso (10 pts).
- **Accumulation model**: Users earn points when they hit each milestone; total score is the sum of all bucket points (0–100).

### Lock & Key (strategic guardrail)

- **Lock (volume)**: Minimum **Total Activation Score ≥ 80**.
- **Key (value)**: At least one **core value action** on controlled products with weight (e.g. weighted count, weighted baixa, or other value-capture milestone).
- This ensures that “busy usage” without real ROI **cannot** be classified as Activated.

### Output buckets for CS / onboarding

At the end of the TTVW, each restaurant is assigned to one of four buckets:

- **🟢 Activated (Green)** – Passed Lock (≥ 80 pts) **and** passed Key (value action present).
- **🟠 Alert – False Positive** – Passed Lock (≥ 80 pts) but **failed** Key (no core value action).
- **🟡 At-Risk (Yellow)** – 40–79 pts; started setup/usage but stalled before real value.
- **🔴 Failure (Red)** – < 40 pts; minimal engagement (“logged in and ghosted”).

These buckets directly drive Customer Success playbooks (no-touch, low-touch, high-touch interventions).

