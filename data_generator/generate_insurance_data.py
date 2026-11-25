"""
Synthetic property & casualty (P&C) insurance data generator.

Simulates two years of a personal-lines carrier (auto, home, renters,
umbrella): new business, mid-term endorsements, renewals, cancellations with
return premium, claims (including a hail catastrophe), and claim financial
transactions (reserves, payments, recoveries).

Output is split into two extracts, the way an upstream system would deliver
them to a Snowflake stage:

    data/raw/load_1/*.csv   everything processed up to 2025-06-30
    data/raw/load_2/*.csv   changes processed 2025-07-01 .. 2025-12-31
                            (plus a few re-delivered duplicates, to prove the
                             incremental models are idempotent)

All data is fake.

Usage:
    python data_generator/generate_insurance_data.py --out data/raw
"""

from __future__ import annotations

import argparse
import csv
import math
import random
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

START = date(2024, 1, 1)
END = date(2025, 12, 31)
CUTOFF = datetime(2025, 6, 30, 23, 59, 59)

FIRST = [
    "James",
    "Mary",
    "Robert",
    "Linda",
    "Michael",
    "Susan",
    "David",
    "Karen",
    "Priya",
    "Arjun",
    "Wei",
    "Mei",
    "Carlos",
    "Sofia",
    "Ahmed",
    "Fatima",
    "Olivia",
    "Noah",
    "Emma",
    "Liam",
    "Ava",
    "Ethan",
]
LAST = [
    "Smith",
    "Johnson",
    "Brown",
    "Garcia",
    "Miller",
    "Davis",
    "Patel",
    "Reddy",
    "Chen",
    "Nguyen",
    "Kim",
    "Khan",
    "Lopez",
    "Wilson",
    "Taylor",
    "Anderson",
    "Thomas",
    "Moore",
]
GEO = [
    ("Madison", "WI", "53703"),
    ("Milwaukee", "WI", "53202"),
    ("Minneapolis", "MN", "55401"),
    ("Des Moines", "IA", "50309"),
    ("Chicago", "IL", "60601"),
    ("Dallas", "TX", "75201"),
    ("Austin", "TX", "78701"),
    ("Denver", "CO", "80202"),
    ("Kansas City", "MO", "64105"),
    ("Columbus", "OH", "43215"),
]
REGIONS = {
    "WI": "Midwest",
    "MN": "Midwest",
    "IA": "Midwest",
    "IL": "Midwest",
    "MO": "Midwest",
    "OH": "Midwest",
    "TX": "South",
    "CO": "West",
}

PRODUCTS = {
    # term months, base annual premium range, annual claim frequency, severity (lognormal mu, sigma)
    "AUTO": (6, (900, 2400), 0.16, (8.0, 0.9)),
    "HOME": (12, (1100, 3200), 0.08, (8.9, 1.1)),
    "RENTERS": (12, (150, 400), 0.04, (7.3, 0.8)),
    "UMBRELLA": (12, (250, 600), 0.006, (10.5, 0.7)),
}
COVERAGES = {
    "AUTO": [("BI", 100_000, 0, 0.35), ("PD", 50_000, 0, 0.20), ("COLL", 0, 500, 0.30), ("COMP", 0, 250, 0.15)],
    "HOME": [("DWELL", 350_000, 1_000, 0.65), ("CONTENTS", 175_000, 1_000, 0.20), ("LIAB", 300_000, 0, 0.15)],
    "RENTERS": [("CONTENTS", 30_000, 500, 0.70), ("LIAB", 100_000, 0, 0.30)],
    "UMBRELLA": [("XS_LIAB", 1_000_000, 0, 1.00)],
}
CAUSES = {
    "AUTO": ["COLLISION", "COLLISION", "COMPREHENSIVE", "GLASS", "BODILY_INJURY"],
    "HOME": ["WIND_HAIL", "WATER", "WATER", "FIRE", "THEFT", "LIABILITY"],
    "RENTERS": ["THEFT", "WATER", "FIRE"],
    "UMBRELLA": ["LIABILITY"],
}
CAT_DATE, CAT_STATE, CAT_CODE = date(2025, 5, 12), "TX", "CAT-2025-TX-HAIL"


def ts(d: date, rng: random.Random, max_lag_days: int = 0) -> datetime:
    return datetime.combine(d, datetime.min.time()) + timedelta(
        days=rng.randint(0, max_lag_days), seconds=rng.randint(6 * 3600, 20 * 3600)
    )


def add_months(d: date, months: int) -> date:
    m = d.month - 1 + months
    y, m = d.year + m // 12, m % 12 + 1
    days = [31, 29 if y % 4 == 0 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    return date(y, m, min(d.day, days))


def poisson(rng: random.Random, lam: float) -> int:
    k, p, L = 0, 1.0, math.exp(-lam)
    while True:
        p *= rng.random()
        if p <= L:
            return k
        k += 1


@dataclass
class Sim:
    rng: random.Random
    customers: list[dict] = field(default_factory=list)
    customer_changes: list[dict] = field(default_factory=list)
    agents: list[dict] = field(default_factory=list)
    policy_txns: list[dict] = field(default_factory=list)
    coverages: list[dict] = field(default_factory=list)
    claims: list[dict] = field(default_factory=list)
    claim_txns: list[dict] = field(default_factory=list)
    seq: dict = field(default_factory=lambda: {"pt": 0, "clm": 0, "ct": 0, "pol": 0})

    def nxt(self, k: str) -> int:
        self.seq[k] += 1
        return self.seq[k]

    # ---------------------------------------------------------------- parties
    def make_agents(self, n: int) -> None:
        r = self.rng
        for i in range(1, n + 1):
            city, state, _ = r.choice(GEO)
            self.agents.append(
                {
                    "agent_id": f"AG{i:04d}",
                    "agent_name": f"{r.choice(FIRST)} {r.choice(LAST)}",
                    "agency_name": f"{r.choice(LAST)} Insurance Agency",
                    "state": state,
                    "region": REGIONS[state],
                    "commission_rate": r.choice([0.08, 0.10, 0.12, 0.15]),
                    "hire_date": (date(2010, 1, 1) + timedelta(days=r.randint(0, 4800))).isoformat(),
                    "updated_at": "2023-12-01 09:00:00",
                }
            )

    def make_customers(self, n: int) -> None:
        r = self.rng
        for i in range(1, n + 1):
            city, state, zipc = r.choice(GEO)
            first, last = r.choice(FIRST), r.choice(LAST)
            c = {
                "customer_id": f"CU{i:06d}",
                "first_name": first,
                "last_name": last,
                "email": f"{first}.{last}{r.randint(1, 999)}@example.com".lower(),
                "phone": f"555-{r.randint(100, 999)}-{r.randint(1000, 9999)}",
                "date_of_birth": (date(1945, 1, 1) + timedelta(days=r.randint(0, 365 * 58))).isoformat(),
                "address_line1": f"{r.randint(10, 9999)} {r.choice(['Oak', 'Elm', 'Main', 'Lake', 'Pine'])} Ave",
                "city": city,
                "state": state,
                "zip_code": zipc,
                "credit_tier": r.choice(["A", "A", "B", "B", "C"]),
                "updated_at": "2023-12-01 09:00:00",
            }
            self.customers.append(c)
            if r.random() < 0.12:  # relocation or credit re-score during 2025 -> SCD2 history
                when = datetime(2025, r.randint(2, 11), r.randint(1, 28), r.randint(8, 18))
                changed = dict(c)
                if r.random() < 0.6:
                    changed["city"], changed["state"], changed["zip_code"] = r.choice(GEO)
                    changed["address_line1"] = f"{r.randint(10, 9999)} Maple Dr"
                else:
                    changed["credit_tier"] = r.choice([t for t in "ABC" if t != c["credit_tier"]])
                changed["updated_at"] = when.strftime("%Y-%m-%d %H:%M:%S")
                self.customer_changes.append(changed)

    # --------------------------------------------------------------- policies
    def _ptxn(self, pol: dict, txn_type: str, eff: date, term_eff: date, term_exp: date, premium: float) -> None:
        self.policy_txns.append(
            {
                "policy_txn_id": f"PT{self.nxt('pt'):08d}",
                "policy_id": pol["policy_id"],
                "policy_number": pol["policy_number"],
                "customer_id": pol["customer_id"],
                "agent_id": pol["agent_id"],
                "product_line": pol["product"],
                "risk_state": pol["state"],
                "txn_type": txn_type,
                "txn_effective_date": eff.isoformat(),
                "term_effective_date": term_eff.isoformat(),
                "term_expiration_date": term_exp.isoformat(),
                "written_premium": round(premium, 2),
                "processed_at": ts(eff, self.rng, 3).strftime("%Y-%m-%d %H:%M:%S"),
            }
        )

    def make_policies(self) -> None:
        r = self.rng
        for cust in self.customers:
            products = ["AUTO"] if r.random() < 0.7 else []
            products += ["HOME"] if r.random() < 0.45 else (["RENTERS"] if r.random() < 0.25 else [])
            if products and r.random() < 0.05:
                products.append("UMBRELLA")
            for prod in products:
                n = self.nxt("pol")
                pol = {
                    "policy_id": f"P{n:07d}",
                    "policy_number": f"{prod[:2]}-{100000 + n}",
                    "customer_id": cust["customer_id"],
                    "agent_id": r.choice(self.agents)["agent_id"],
                    "product": prod,
                    "state": cust["state"],
                }
                self._simulate_policy(pol)

    def _simulate_policy(self, pol: dict) -> None:
        r = self.rng
        months, (lo, hi), freq, sev = PRODUCTS[pol["product"]]
        term_eff = START + timedelta(days=r.randint(0, (date(2025, 11, 30) - START).days))
        annual = r.uniform(lo, hi)
        txn_type = "NEW"
        while term_eff <= END:
            term_exp = add_months(term_eff, months)
            term_days = (term_exp - term_eff).days
            term_premium = annual * months / 12
            self._ptxn(pol, txn_type, term_eff, term_eff, term_exp, term_premium)
            for code, limit, ded, share in COVERAGES[pol["product"]]:
                self.coverages.append(
                    {
                        "policy_id": pol["policy_id"],
                        "term_effective_date": term_eff.isoformat(),
                        "coverage_code": code,
                        "limit_amount": limit,
                        "deductible": ded,
                        "coverage_premium": round(term_premium * share, 2),
                    }
                )
            active_until = term_exp
            # Mid-term endorsement: pro-rata premium change for the rest of the term
            if r.random() < 0.15:
                eff = term_eff + timedelta(days=r.randint(15, term_days - 15))
                change = annual * r.choice([-0.12, -0.06, 0.08, 0.15]) * (term_exp - eff).days / 365
                if eff <= END:
                    self._ptxn(pol, "ENDORSEMENT", eff, term_eff, term_exp, change)
                    term_premium += change
            # Cancellation: return the unearned premium
            if r.random() < 0.06:
                eff = term_eff + timedelta(days=r.randint(10, term_days - 5))
                if eff <= END:
                    unearned = term_premium * (term_exp - eff).days / term_days
                    self._ptxn(pol, "CANCELLATION", eff, term_eff, term_exp, -unearned)
                    active_until = eff
            self._simulate_claims(pol, term_eff, min(active_until, END + timedelta(days=1)), freq, sev)
            if active_until < term_exp or r.random() > 0.88:
                break  # cancelled, or non-renewed
            term_eff, txn_type = term_exp, "RENEWAL"
            annual *= r.uniform(1.0, 1.09)  # rate increase at renewal

    # ----------------------------------------------------------------- claims
    def _simulate_claims(self, pol: dict, start: date, end: date, freq: float, sev: tuple) -> None:
        r = self.rng
        days = (end - start).days
        if days <= 0:
            return
        losses = [start + timedelta(days=r.randint(0, days - 1)) for _ in range(poisson(r, freq * days / 365))]
        in_cat_zone = pol["state"] == CAT_STATE and pol["product"] in ("HOME", "AUTO") and start <= CAT_DATE < end

        if in_cat_zone and r.random() < 0.18:
            losses.append(CAT_DATE)
        for loss in losses:
            cat = loss == CAT_DATE and pol["state"] == CAT_STATE
            cause = (
                "WIND_HAIL"
                if cat and pol["product"] == "HOME"
                else ("COMPREHENSIVE" if cat else r.choice(CAUSES[pol["product"]]))
            )
            self._make_claim(pol, loss, cause, CAT_CODE if cat else "", sev)

    def _make_claim(self, pol: dict, loss: date, cause: str, cat: str, sev: tuple) -> None:
        r = self.rng
        reported = loss + timedelta(days=int(r.expovariate(1 / 6)))
        if reported > END:
            return
        claim_id = f"CL{self.nxt('clm'):07d}"
        ultimate = round(max(250.0, r.lognormvariate(*sev)), 2)
        base = {
            "claim_id": claim_id,
            "policy_id": pol["policy_id"],
            "loss_date": loss.isoformat(),
            "reported_date": reported.isoformat(),
            "cause_of_loss": cause,
            "catastrophe_code": cat,
        }
        opened = ts(reported, r, 1)
        self.claims.append(
            {**base, "claim_status": "OPEN", "closed_date": "", "updated_at": opened.strftime("%Y-%m-%d %H:%M:%S")}
        )

        last_processed = [opened]

        def ctx(d: date, kind: str, amount: float) -> None:
            if d > END:
                return
            processed = ts(d, r, 1)
            last_processed[0] = max(last_processed[0], processed)
            self.claim_txns.append(
                {
                    "claim_txn_id": f"CT{self.nxt('ct'):08d}",
                    "claim_id": claim_id,
                    "txn_date": d.isoformat(),
                    "txn_type": kind,
                    "amount": round(amount, 2),
                    "processed_at": processed.strftime("%Y-%m-%d %H:%M:%S"),
                }
            )

        # Case reserve set at first notice, adjusted as the claim develops.
        reserve = round(ultimate * r.uniform(0.6, 1.4), 2)
        ctx(reported, "RESERVE", reserve)
        d, paid = reported, 0.0
        n_pay = r.choice([1, 1, 2, 2, 3, 4])
        for i in range(n_pay):
            d = d + timedelta(days=r.randint(7, 120))
            pay = round((ultimate - paid) if i == n_pay - 1 else ultimate * r.uniform(0.15, 0.5), 2)
            pay = max(0.0, min(pay, ultimate - paid))
            ctx(d, "PAYMENT", pay)
            ctx(d, "RESERVE", -min(pay, reserve))  # payment takes down the reserve
            reserve -= min(pay, reserve)
            paid += pay
        if reserve > 0:
            ctx(d, "RESERVE", -reserve)  # close remaining reserve
        if d <= END:
            # The status closes only after the final payment and reserve take-down have posted.
            closed_at = last_processed[0] + timedelta(hours=1)
            self.claims.append(
                {
                    **base,
                    "claim_status": "CLOSED",
                    "closed_date": d.isoformat(),
                    "updated_at": closed_at.strftime("%Y-%m-%d %H:%M:%S"),
                }
            )
        if cause in ("COLLISION",) and r.random() < 0.15:
            ctx(d + timedelta(days=r.randint(30, 150)), "RECOVERY", round(paid * r.uniform(0.2, 0.6), 2))


def _write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def split(rows: list[dict], col: str) -> tuple[list[dict], list[dict]]:
    first = [x for x in rows if datetime.fromisoformat(x[col]) <= CUTOFF]
    second = [x for x in rows if CUTOFF < datetime.fromisoformat(x[col]) <= datetime(2025, 12, 31, 23, 59, 59)]
    return first, second


def generate(out: Path, seed: int, n_customers: int) -> None:
    rng = random.Random(seed)
    sim = Sim(rng)
    sim.make_agents(40)
    sim.make_customers(n_customers)
    sim.make_policies()

    early_changes = [c for c in sim.customer_changes if datetime.fromisoformat(c["updated_at"]) <= CUTOFF]
    late_changes = [c for c in sim.customer_changes if datetime.fromisoformat(c["updated_at"]) > CUTOFF]
    # Load 1: current state of every customer as of the cutoff
    current = {c["customer_id"]: c for c in sim.customers}
    current.update({c["customer_id"]: c for c in early_changes})

    pt1, pt2 = split(sim.policy_txns, "processed_at")
    cl1, cl2 = split(sim.claims, "updated_at")
    ct1, ct2 = split(sim.claim_txns, "processed_at")
    ct2 = ct2 + rng.sample(ct1, k=25)  # re-delivered rows: incremental models must not double count

    loads = {
        "load_1": {
            "customers": list(current.values()),
            "agents": sim.agents,
            "policy_transactions": pt1,
            "policy_coverages": [c for c in sim.coverages if c["term_effective_date"] <= "2025-06-30"],
            "claims": cl1,
            "claim_transactions": ct1,
        },
        "load_2": {
            "customers": late_changes,
            "agents": [],
            "policy_transactions": pt2,
            "policy_coverages": [c for c in sim.coverages if c["term_effective_date"] > "2025-06-30"],
            "claims": cl2,
            "claim_transactions": ct2,
        },
    }
    for load, tables in loads.items():
        for name, rows in tables.items():
            if rows:
                _write(out / load / f"{name}.csv", rows)
        print(load, {k: len(v) for k, v in tables.items()})


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=Path("data/raw"))
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--customers", type=int, default=3000)
    a = p.parse_args()
    generate(a.out, a.seed, a.customers)


if __name__ == "__main__":
    main()
