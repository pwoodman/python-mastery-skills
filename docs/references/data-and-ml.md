# Data & ML — pandas, NumPy, scikit-learn, PyTorch

## Table of Contents
1. pandas — Data Manipulation
2. NumPy — Numerical Computing
3. scikit-learn — ML Pipelines
4. PyTorch — Deep Learning Patterns
5. Data Pipeline Design
6. Performance Patterns

---

## 1. pandas — Data Manipulation

### Loading & Inspecting

```python
import pandas as pd

df = pd.read_csv("data.csv", parse_dates=["created_at"])
df = pd.read_parquet("data.parquet")           # much faster than CSV for large data
df = pd.read_json("data.json", lines=True)     # JSON Lines format

# Always inspect first
df.shape          # (rows, cols)
df.dtypes         # column types
df.head(5)
df.describe()     # statistics for numeric columns
df.isnull().sum() # missing value counts per column
df.info()         # memory usage + non-null counts
```

### Selecting & Filtering

```python
# Column access
df["name"]                        # Series
df[["name", "email"]]             # DataFrame

# Row filtering
active = df[df["is_active"] == True]
recent = df[df["created_at"] > "2024-01-01"]

# Multiple conditions — use & | ~ with parentheses
filtered = df[(df["score"] > 80) & (df["region"] == "US")]

# .loc for label-based, .iloc for position-based
df.loc[df["email"].str.endswith("@company.com"), "is_employee"] = True
df.iloc[0:10, 2:5]

# query() — readable for complex filters
df.query("score > 80 and region == 'US'")
df.query("name in @approved_names")   # use @ to reference Python variable
```

### Transforming

```python
# Apply a function to a column
df["email_domain"] = df["email"].str.split("@").str[1]
df["score_normalized"] = (df["score"] - df["score"].mean()) / df["score"].std()

# Map values
df["tier"] = df["score"].map({1: "low", 2: "mid", 3: "high"})

# Vectorized string operations (faster than apply)
df["name_upper"] = df["name"].str.upper()
df["is_gmail"] = df["email"].str.contains("@gmail.com")

# apply — for complex per-row logic (slower, use only when needed)
df["label"] = df.apply(lambda row: classify(row["score"], row["region"]), axis=1)

# cut / qcut — bin continuous into categorical
df["age_bucket"] = pd.cut(df["age"], bins=[0, 18, 35, 60, 100], labels=["youth", "young", "mid", "senior"])
```

### Grouping & Aggregation

```python
# groupby + agg
summary = (
    df.groupby("region")
    .agg(
        total_revenue=("amount", "sum"),
        order_count=("order_id", "count"),
        avg_order=("amount", "mean"),
    )
    .reset_index()
    .sort_values("total_revenue", ascending=False)
)

# Multiple group keys
df.groupby(["region", "product_category"])["revenue"].sum()

# transform — add group stats back to original rows
df["region_avg"] = df.groupby("region")["revenue"].transform("mean")
df["is_above_avg"] = df["revenue"] > df["region_avg"]
```

### Missing Data

```python
df.dropna(subset=["email", "name"])        # drop rows with nulls in key columns
df["score"].fillna(df["score"].median())   # fill with median
df.ffill()                                 # forward fill time series

# Check before using
if df["amount"].isnull().any():
    raise DataValidationError("amount column contains nulls")
```

### Working with Dates

```python
df["created_at"] = pd.to_datetime(df["created_at"], utc=True)   # ensure tz-aware
df["year_month"] = df["created_at"].dt.to_period("M")
df["day_of_week"] = df["created_at"].dt.day_name()
df["days_since"] = (pd.Timestamp.now(tz="UTC") - df["created_at"]).dt.days
```

### Performance Habits

```python
# Read only needed columns
df = pd.read_csv("big_file.csv", usecols=["id", "amount", "status"])

# Downcasting dtypes saves memory
df["amount"] = pd.to_numeric(df["amount"], downcast="float")
df["count"] = df["count"].astype("int32")    # vs int64 default

# Use .str methods and vectorized ops over .apply()
# Parquet over CSV for large files — 10-50x faster to read
# Category dtype for low-cardinality string columns
df["status"] = df["status"].astype("category")

# Chunked reading for files larger than RAM
for chunk in pd.read_csv("huge.csv", chunksize=100_000):
    process(chunk)
```

---

## 2. NumPy — Numerical Computing

```python
import numpy as np

# Array creation
arr = np.array([1, 2, 3, 4, 5])
zeros = np.zeros((3, 4))           # 3×4 of zeros
ones  = np.ones((3, 4))
eye   = np.eye(3)                  # 3×3 identity matrix
rng   = np.random.default_rng(42)  # reproducible RNG (modern API)
rand  = rng.random((100, 10))

# Vectorized operations — avoid Python loops over arrays
prices = np.array([10.0, 20.0, 30.0])
discounted = prices * 0.9          # multiply all by 0.9 at once
tax = prices * np.array([0.05, 0.07, 0.05])  # element-wise

# Boolean indexing
above_threshold = arr[arr > 3]     # [4, 5]
arr[arr < 0] = 0                   # clip negatives to zero

# Aggregations
arr.sum(), arr.mean(), arr.std()
arr.max(), arr.argmax()            # value and index of max
np.sort(arr), np.argsort(arr)

# Reshaping
arr.reshape(5, 1)                  # column vector
arr.flatten()
np.concatenate([a, b], axis=0)
np.vstack([row1, row2])
np.hstack([col1, col2])

# Linear algebra
np.dot(A, B)                       # matrix multiply
A @ B                              # same, cleaner syntax
np.linalg.norm(v)                  # vector norm
np.linalg.solve(A, b)             # solve Ax = b

# Memory efficiency
arr.nbytes                         # total bytes
arr.astype(np.float32)             # vs float64 — halves memory for large arrays
```

---

## 3. scikit-learn — ML Pipelines

### The Golden Rule: Always Use a Pipeline

```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.impute import SimpleImputer
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.metrics import classification_report

# Train/test split — do this FIRST, before any preprocessing
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# Column-specific transformations
numeric_features = ["age", "income", "score"]
categorical_features = ["region", "tier"]

preprocessor = ColumnTransformer(transformers=[
    ("num", Pipeline([
        ("impute", SimpleImputer(strategy="median")),
        ("scale",  StandardScaler()),
    ]), numeric_features),
    ("cat", Pipeline([
        ("impute", SimpleImputer(strategy="most_frequent")),
        ("encode", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
    ]), categorical_features),
])

# Full pipeline — preprocessor + model
model = Pipeline([
    ("prep",    preprocessor),
    ("clf",     RandomForestClassifier(n_estimators=100, random_state=42)),
])

# Fit only on training data — prevents data leakage
model.fit(X_train, y_train)

# Evaluate
y_pred = model.predict(X_test)
print(classification_report(y_test, y_pred))

# Cross-validation
scores = cross_val_score(model, X_train, y_train, cv=5, scoring="f1_weighted")
print(f"CV F1: {scores.mean():.3f} ± {scores.std():.3f}")
```

### Saving and Loading Models

```python
import joblib

joblib.dump(model, "model.joblib")
loaded_model = joblib.load("model.joblib")
```

---

## 4. PyTorch — Deep Learning Patterns

### Device Management

```python
import torch

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
# For Apple Silicon
device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")

model = model.to(device)
X = X.to(device)
```

### Model Definition

```python
import torch.nn as nn

class MLP(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, output_dim: int) -> None:
        super().__init__()
        self.network = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, output_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.network(x)
```

### Training Loop

```python
model = MLP(128, 256, 10).to(device)
optimizer = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
criterion = nn.CrossEntropyLoss()
scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=50)

for epoch in range(num_epochs):
    # Training
    model.train()
    for X_batch, y_batch in train_loader:
        X_batch, y_batch = X_batch.to(device), y_batch.to(device)
        optimizer.zero_grad()
        outputs = model(X_batch)
        loss = criterion(outputs, y_batch)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()

    # Validation
    model.eval()
    with torch.no_grad():
        val_loss = evaluate(model, val_loader, criterion, device)

    scheduler.step()
    print(f"Epoch {epoch+1}: val_loss={val_loss:.4f}")

# Save
torch.save({"model_state_dict": model.state_dict(), "epoch": epoch}, "checkpoint.pt")

# Load
checkpoint = torch.load("checkpoint.pt", map_location=device)
model.load_state_dict(checkpoint["model_state_dict"])
```

### DataLoader

```python
from torch.utils.data import Dataset, DataLoader
import torch

class TabularDataset(Dataset):
    def __init__(self, X: np.ndarray, y: np.ndarray) -> None:
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.long)

    def __len__(self) -> int:
        return len(self.X)

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        return self.X[idx], self.y[idx]

train_loader = DataLoader(
    train_dataset,
    batch_size=64,
    shuffle=True,
    num_workers=4,
    pin_memory=True,   # faster GPU transfer
)
```

---

## 5. Data Pipeline Design

```python
from dataclasses import dataclass
from typing import Iterator

@dataclass
class PipelineStep:
    """Each step is a callable that transforms a DataFrame."""
    name: str

class DataPipeline:
    def __init__(self) -> None:
        self._steps: list[tuple[str, callable]] = []

    def add_step(self, name: str, fn: callable) -> "DataPipeline":
        self._steps.append((name, fn))
        return self   # enable chaining

    def run(self, df: pd.DataFrame) -> pd.DataFrame:
        for name, step in self._steps:
            logger.info("Running pipeline step: %s, rows=%d", name, len(df))
            df = step(df)
        return df

pipeline = (
    DataPipeline()
    .add_step("drop_nulls",     lambda df: df.dropna(subset=["id", "amount"]))
    .add_step("normalize_email", lambda df: df.assign(email=df["email"].str.lower()))
    .add_step("compute_tier",   compute_customer_tier)
)
result = pipeline.run(raw_df)
```

---

## 6. Performance Patterns

```python
# Profiling memory usage
import tracemalloc
tracemalloc.start()
process_data(df)
snapshot = tracemalloc.take_snapshot()
for stat in snapshot.statistics("lineno")[:10]:
    print(stat)

# Chunked processing for large files
def process_large_file(path: str) -> pd.DataFrame:
    chunks = []
    for chunk in pd.read_parquet(path, chunksize=10_000):  # if supported
        processed = transform(chunk)
        chunks.append(processed)
    return pd.concat(chunks, ignore_index=True)

# Use polars for 10-100x speedup on large data (alternative to pandas)
import polars as pl   # pip install polars
df = pl.read_parquet("big.parquet")
result = df.filter(pl.col("amount") > 100).group_by("region").agg(pl.col("amount").sum())
```
