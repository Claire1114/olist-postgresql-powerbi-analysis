# Driving Repurchase Intent: Olist Regional Logistics & Loyalty Analysis
This project analyzes the relationship between regional logistics conditions and customer repeat purchasing behavior using the Olist Brazilian e-commerce dataset.

The analysis focuses on four potential retention drivers:

- Freight costs
- Cross-state shipping
- Shipping duration
- Review scores

Customer activity was aggregated using `customer_unique_id`, and only successfully delivered orders were included. A six-month maturity filter was applied to ensure customers had sufficient time to make a repeat purchase.

The final analysis compares logistics and retention performance across Brazilian states and identifies markets where freight discounts, delivery improvements, or regional inventory strategies may support customer loyalty.

## Tools

- **Python, Pandas, SQLAlchemy:** Migrated data from SQLite to PostgreSQL
- **PostgreSQL:** Data validation, cohort construction, exploratory analysis, and analytical table creation
- **Power BI:** Interactive dashboards and regional comparison

## Repository Contents

- `sql/` — PostgreSQL validation, exploratory analysis, cohort construction, and analytical data 
- `presentation/` — Project presentation in PowerPoint and PDF formats
- `powerbi/` — Power BI dashboard information and online report link
