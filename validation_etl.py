import pandas as pd
from sqlalchemy import create_engine, text
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


def validate_completeness(engine):
    segment_df = pd.read_csv('segmentation.csv', delimiter=';')
    usage_df = pd.read_csv('product_usage.csv', delimiter=';')
    merchants_result = pd.read_sql('SELECT * FROM Merchants', engine)
    usage_result = pd.read_sql('SELECT * FROM Product_Usage', engine)
    assert len(segment_df) <= len(merchants_result) * 1.1, "Significant data loss in Merchants"
    assert len(usage_df) <= len(usage_result) * 1.1, "Significant data loss in Product_Usage"
    logging.info("Data completeness validated")

def validate_integrity(engine):
    usage_result = pd.read_sql('SELECT * FROM Product_Usage', engine)
    assert usage_result['merchant_id'].isnull().sum() == 0, "Nulls in merchant_id"
    assert usage_result.duplicated(subset=['merchant_id', 'date_id', 'event_id']).sum() == 0, "Duplicates in Product_Usage"
    logging.info("Data integrity validated")

def validate_types(engine):
    usage_result = pd.read_sql('SELECT * FROM Product_Usage', engine)
    assert usage_result['count_of_events'].dtype == 'int64', "Incorrect type for count_of_events"
    assert usage_result['usd_amount'].dtype == 'float64', "Incorrect type for usd_amount"
    assert usage_result['merchant_id'].dtype == 'object', "Incorrect type for merchant_id"
    assert usage_result['date_id'].str.match(r'^\d{4}-\d{2}-\d{2}$').all(), "Invalid date_id format"
    logging.info("Data types validated")

def validate_foreign_keys(engine):
    query = "SELECT COUNT(*) FROM Product_Usage pu LEFT JOIN Merchants m ON pu.merchant_id = m.merchant_id WHERE m.merchant_id IS NULL"
    orphans = pd.read_sql(query, engine).iloc[0, 0]
    assert orphans == 0, f"{orphans} merchant_id orphans found"
    query = "SELECT COUNT(*) FROM Product_Usage pu LEFT JOIN Dates d ON pu.date_id = d.date_id WHERE d.date_id IS NULL"
    orphans = pd.read_sql(query, engine).iloc[0, 0]
    assert orphans == 0, f"{orphans} date_id orphans found"
    logging.info("Foreign key integrity validated")

def validate_business_rules(engine):
    # Join Product_Usage with Events to get event_name
    query = """
    SELECT pu.*, e.event_name
    FROM Product_Usage pu
    LEFT JOIN Events e ON pu.event_id = e.event_id
    """
    usage_result = pd.read_sql(query, engine)

    non_monetary_events = ['Cart.ViewItem', 'Cart.AddItem', 'Cart.Checkout']
    monetary_mask = ~usage_result['event_name'].isin(non_monetary_events)
    assert usage_result.loc[monetary_mask, 'usd_amount'].notna().all(), "Missing usd_amount for monetary events"
    assert (usage_result.loc[monetary_mask, 'usd_amount'] >= 0).all(), "Negative usd_amount for monetary events"
    assert usage_result.loc[~monetary_mask, 'usd_amount'].isna().all(), "usd_amount should be null for non-monetary events"
    assert (usage_result['count_of_events'] >= 0).all(), "Negative count_of_events found"
    logging.info("Business rules validated")

def validate_event_completeness(engine):
    expected_events = ['Charge', 'Subscription.Charge', 'Marketplace.Charge', 'Cart.AddItem', 'Cart.Checkout', 'Cart.PaymentSubmit', 'Cart.ViewItem']
    events_result = pd.read_sql('SELECT DISTINCT event_name FROM Events', engine)
    actual_events = events_result['event_name'].tolist()
    missing_events = [event for event in expected_events if event not in actual_events]
    assert not missing_events, f"Missing expected events: {missing_events}"
    logging.info("Event completeness validated")