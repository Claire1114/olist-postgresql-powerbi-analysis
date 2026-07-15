# SQL Workflow

This folder contains the data import, database validation, exploratory analysis, customer cohort construction, and logistics analysis used in this project.

## Files

- `01_import_sqlite_to_postgresql.ipynb`  
  Imports the Olist SQLite tables into PostgreSQL using Python, Pandas, and SQLAlchemy.

- `02_schema_validation_and_constraints.sql`  
  Validates table relationships and creates primary key and foreign key constraints.

- `03_customer_and_order_exploration.sql`  
  Explores order status, customer retention, repurchase behavior, and order structure.

- `04_customer_cohort_and_logistics_analysis.sql`  
  Builds the mature customer cohort, analyzes freight costs, shipping duration, cross-state orders, and creates Power BI analytical tables.
