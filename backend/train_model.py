"""
train_model.py
──────────────
Train, evaluate and save the loan risk model.

    python train_model.py                      # synthetic data (default 150k rows)
    python train_model.py --data loans.csv     # your own historical data
    python train_model.py --cv 5               # also run 5-fold cross-validation
    python train_model.py --no-save            # evaluate only

CSV format (one row per past application):
    monthly_income, loan_amount, existing_emis, employment_years,
    credit_score, num_dependents, [tenure_months], [interest_rate], risk_level
where risk_level is LOW / MEDIUM / HIGH.

The script compares the new model with the previous Random Forest, checks
that predictions behave logically, writes model_report.json, and only saves
the model when it is at least as good as the one already in use.
"""

import argparse
import os
import time
from datetime import datetime, timezone

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score, log_loss, recall_score, roc_auc_score,
)
from sklearn.model_selection import StratifiedKFold, train_test_split

import risk_model as rm

LABELS = rm.LABELS
W = np.array([0.0, 50.0, 100.0])  # LOW, MEDIUM, HIGH → 0–100 score


# ── Data ──────────────────────────────────────────────────────────────────────

def load_csv(path: str, label_col: str):
    import pandas as pd

    df = pd.read_csv(path)
    required = ["monthly_income", "loan_amount", "existing_emis",
                "employment_years", "credit_score", "num_dependents", label_col]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise SystemExit(f"CSV is missing columns: {', '.join(missing)}")
    df = df.dropna(subset=required)
    df[label_col] = df[label_col].astype(str).str.strip().str.upper()
    df = df[df[label_col].isin(LABELS)]
    df["tenure_months"] = df.get("tenure_months", 60)
    df["interest_rate"] = df.get("interest_rate", 10.5)
    raw = df[["monthly_income", "loan_amount", "existing_emis", "employment_years",
              "credit_score", "num_dependents", "tenure_months", "interest_rate"]] \
        .astype(float).fillna({"tenure_months": 60, "interest_rate": 10.5}).to_numpy()
    return raw, df[label_col].to_numpy()


def label_raw(raw):
    X = rm.feature_matrix(raw)
    return np.array([rm._label(*row[:6], row[6]) for row in X])


# ── Evaluation ────────────────────────────────────────────────────────────────

def ordered_proba(model, X):
    """Probabilities as columns [LOW, MEDIUM, HIGH] for any model."""
    P = model.predict_proba(X)
    classes = list(model.classes_)
    return P[:, [classes.index(c) for c in LABELS]]


def logic_checks(model, raw):
    """
    % of applicants whose risk score goes UP after an improvement that
    should only ever lower risk. Ideal: 0 everywhere.
    """
    base = ordered_proba(model, rm.feature_matrix(raw)) @ W
    tweaks = {
        "credit score +50": (4, lambda c: np.clip(c + 50, 300, 900)),
        "employment +3 yrs": (3, lambda c: c + 3),
        "income +25%": (0, lambda c: c * 1.25),
        "existing EMIs -40%": (2, lambda c: c * 0.6),
        "loan amount -20%": (1, lambda c: c * 0.8),
    }
    out = {}
    for name, (col, fn) in tweaks.items():
        r2 = raw.copy()
        r2[:, col] = fn(r2[:, col])
        after = ordered_proba(model, rm.feature_matrix(r2)) @ W
        out[name] = round(float(np.mean(after > base + 0.5) * 100), 3)
    return out


def evaluate(model, raw, y):
    X = rm.feature_matrix(raw)
    P = np.clip(ordered_proba(model, X), 1e-7, 1)
    P = P / P.sum(1, keepdims=True)
    pred = np.array(LABELS)[P.argmax(1)]
    sorted_labels = sorted(LABELS)
    P_sorted = P[:, [LABELS.index(c) for c in sorted_labels]]

    t = time.perf_counter()
    for i in range(200):
        model.predict_proba(X[i % len(X): i % len(X) + 1])
    latency = (time.perf_counter() - t) / 200 * 1000

    return {
        "accuracy": round(float(accuracy_score(y, pred)), 4),
        "macro_f1": round(float(f1_score(y, pred, average="macro")), 4),
        "recall_by_class": {c: round(float(r), 4) for c, r in
                            zip(LABELS, recall_score(y, pred, labels=LABELS, average=None))},
        "log_loss": round(float(log_loss(y, P_sorted, labels=sorted_labels)), 4),
        "roc_auc_ovr": round(float(roc_auc_score(y, P_sorted, multi_class="ovr",
                                                 labels=sorted_labels)), 4),
        # HIGH predicted as LOW is the costliest mistake for a lender.
        "high_risk_marked_low": int(np.sum((y == "HIGH") & (pred == "LOW"))),
        "confusion_matrix": {"labels": LABELS,
                             "matrix": confusion_matrix(y, pred, labels=LABELS).tolist()},
        "illogical_changes_pct": logic_checks(model, raw[:5000]),
        # How finely the 0–100 score moves (more = smoother live gauge).
        "distinct_score_values": int(len(np.unique(np.round(P @ W)))),
        "latency_ms": round(latency, 2),
        "test_rows": int(len(y)),
    }


def baseline_rf():
    """The previous production model (v2) for comparison."""
    return RandomForestClassifier(n_estimators=150, max_depth=12, min_samples_leaf=3,
                                  random_state=42, n_jobs=-1)


def cross_validate(raw, y, folds, y_eval=None):
    """Train on y; score each fold against y_eval (clean policy labels for synthetic data)."""
    X = rm.feature_matrix(raw)
    y_eval = y if y_eval is None else y_eval
    scores = []
    for i, (tr, te) in enumerate(StratifiedKFold(folds, shuffle=True, random_state=0).split(X, y)):
        m = rm.OrdinalRiskModel().fit(X[tr], y[tr])
        pred = m.predict(X[te])
        scores.append(f1_score(y_eval[te], pred, average="macro"))
        print(f"  fold {i + 1}/{folds}: macro F1 {scores[-1]:.4f}")
    return {"folds": folds, "macro_f1_mean": round(float(np.mean(scores)), 4),
            "macro_f1_std": round(float(np.std(scores)), 4)}


# ── Main ──────────────────────────────────────────────────────────────────────

def print_metrics(title, m):
    print(f"\n{title}")
    print(f"  accuracy {m['accuracy']:.4f} | macro F1 {m['macro_f1']:.4f} | "
          f"log loss {m['log_loss']:.4f} | AUC {m['roc_auc_ovr']:.4f} | {m['latency_ms']} ms | "
          f"{m['distinct_score_values']} distinct scores")
    print(f"  recall LOW/MED/HIGH: {m['recall_by_class']}")
    print(f"  HIGH-risk applicants marked LOW: {m['high_risk_marked_low']}")
    print(f"  illogical score changes (%): {m['illogical_changes_pct']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", help="CSV of historical applications (see format above)")
    ap.add_argument("--label-col", default="risk_level")
    ap.add_argument("--rows", type=int, default=150_000, help="synthetic training rows")
    ap.add_argument("--noise", type=float, default=rm.LABEL_NOISE,
                    help="label uncertainty near cut-offs for synthetic data (0 = exact rules)")
    ap.add_argument("--cv", type=int, default=0, help="k-fold cross-validation (0 = off)")
    ap.add_argument("--no-save", action="store_true")
    ap.add_argument("--force", action="store_true", help="save even if worse than the current model")
    args = ap.parse_args()

    if args.data:
        raw, y = load_csv(args.data, args.label_col)
        source = f"csv:{os.path.basename(args.data)}"
        raw_tr, raw_te, y_tr, y_te = train_test_split(raw, y, test_size=0.2, stratify=y, random_state=42)
    else:
        source = "synthetic"
        raw_tr = rm.synthetic_raw(args.rows, seed=7)
        # Train on labels with realistic uncertainty near cut-offs;
        # test against the clean policy so accuracy = agreement with policy.
        y_tr = rm.policy_labels(rm.feature_matrix(raw_tr), args.noise, seed=7)
        raw_te = rm.synthetic_raw(20_000, seed=999)   # independent hold-out set
        y_te = label_raw(raw_te)
    print(f"[train] source={source} train={len(y_tr)} test={len(y_te)} "
          f"class mix={dict(zip(*np.unique(y_tr, return_counts=True)))}")

    t = time.perf_counter()
    model = rm.OrdinalRiskModel().fit(rm.feature_matrix(raw_tr), y_tr)
    fit_s = time.perf_counter() - t
    metrics = evaluate(model, raw_te, y_te)
    print_metrics(f"New model v{rm.MODEL_VERSION} (trained in {fit_s:.1f}s)", metrics)

    rf_y = y_tr[:6000] if args.data else label_raw(raw_tr[:6000])  # v2 used exact-rule labels
    rf = baseline_rf().fit(rm.feature_matrix(raw_tr[:6000]), rf_y)
    base = evaluate(rf, raw_te, y_te)
    print_metrics("Previous model (Random Forest, 6k rows)", base)

    current = None
    if os.path.exists(rm.MODEL_PATH):
        try:
            import joblib
            bundle = joblib.load(rm.MODEL_PATH)
            current = evaluate(bundle["pipeline"], raw_te, y_te)
            print_metrics(f"Model currently saved (v{bundle.get('version')})", current)
        except Exception as e:  # noqa: BLE001
            print(f"[train] could not evaluate saved model: {e}")

    cv = None
    if args.cv > 1:
        print(f"\nCross-validation ({args.cv} folds)")
        cv = cross_validate(raw_tr, y_tr, args.cv, None if args.data else label_raw(raw_tr))

    report = {
        "version": rm.MODEL_VERSION,
        "algorithm": "Ordinal monotone HistGradientBoosting (2 binary boosters)",
        "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "data_source": source,
        "label_noise": None if args.data else args.noise,
        "train_rows": int(len(y_tr)),
        "features": rm.FEATURES,
        "monotone_constraints": rm.MONOTONE,
        "hyperparameters": rm.HYPERPARAMS,
        "boosting_iterations": [int(m.n_iter_) for m in model.models],
        "fit_seconds": round(fit_s, 1),
        "test_metrics": metrics,
        "previous_model_metrics": base,
        "cross_validation": cv,
    }

    if args.no_save:
        print("\n[train] --no-save: model not written")
        return
    if current and current["macro_f1"] > metrics["macro_f1"] + 1e-4 and not args.force:
        print("\n[train] Saved model scores higher — keeping it (use --force to overwrite)")
        return
    if args.data:  # evaluated on a hold-out split; final model uses all rows
        model = rm.OrdinalRiskModel().fit(rm.feature_matrix(raw), y)
        report["train_rows"] = int(len(y))
    rm.save(model, report)
    print(f"[train] Report written to {rm.REPORT_PATH}")


if __name__ == "__main__":
    main()
