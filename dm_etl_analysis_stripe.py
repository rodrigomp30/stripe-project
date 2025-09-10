# Setup Cell

import pandas as pd
from sqlalchemy import create_engine, text
import logging
from validation_etl import validate_completeness, validate_integrity, validate_types, validate_foreign_keys, validate_business_rules, validate_event_completeness

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')



def extract(segment_file='segmentation.csv', usage_file='product_usage.csv'):
    
    """Extract data from the CSV file"""
    logging.info('Extracting data...')
    
    try:
        segment_df = pd.read_csv(segment_file, delimiter=';')
        usage_df = pd.read_csv(usage_file, delimiter=';')
        return segment_df, usage_df
    except Exception as e:
        logging.error(f'Extraction failed with erro: {e}')
        raise



def transform(segment_df, usage_df, engine):
    
    """Transform data to fit the schema"""
    logging.info('Transforming data...')
    
    try:
        # Merchants: Map segment data
        segment_df.columns = segment_df.columns.str.strip().str.lower()
        merchants_df = segment_df.melt(
            id_vars = ['merchant'],
            value_vars = ['saas', 'ecommerce', 'platforms'],
            var_name = 'segment',
            value_name = 'is_segment'
            ).query('is_segment == 1')[['merchant', 'segment']].rename(columns={'merchant': 'merchant_id'})

        # Products: Extract unique products
        usage_df = usage_df.rename(columns={
            'Merchant': 'merchant_id', 
            'Date': 'date', 
            'Product': 'product', 
            'Event': 'event', 
            'Count of events': 'count_of_events',
            'Usd Amount': 'usd_amount'})

        products_df = pd.DataFrame(usage_df['product'].dropna().unique(), columns=['product_name'])

        # Events: Extract unique events and map to products
        events_df = usage_df[['product', 'event']].dropna().drop_duplicates()

            # Dates: Standardize dates to YYYY-MM
        dates_df = usage_df[['date']].drop_duplicates()
        dates_df['date'] = pd.to_datetime(dates_df['date'])
        dates_df['date_id'] = dates_df['date'].dt.strftime('%Y-%m-%d')
        dates_df['month'] = dates_df['date'].dt.month
        dates_df['year'] = dates_df['date'].dt.year
        dates_df = dates_df[['date_id', 'month', 'year']].dropna()
        # dates_df['date'] = dates_df['date'].dt.to_pydatetime()

        # Product_Usage: Transform usage data
        usage_df['usd_amount'] = usage_df['usd_amount'] / 100  # Convert cents to USD
        
        non_monetary_events = ['Cart.ViewItem', 'Cart.AddItem', 'Cart.Checkout']
        events_with_ids = pd.read_sql("SELECT event_id, event_name FROM Events", engine)  # Now accessible
        usage_df = usage_df.merge(events_with_ids, left_on='event', right_on='event_name', how='left')
        
        usage_df.loc[usage_df['event'].isin(non_monetary_events), 'usd_amount'] = None
        
        usage_df['date_id'] = pd.to_datetime(usage_df['date']).dt.strftime('%Y-%m-%d')
        usage_df = usage_df.merge(merchants_df, on='merchant_id', how='left')
        usage_df = usage_df.groupby(['merchant_id', 'date_id', 'event', 'product', 'segment']).agg({
            'count_of_events': 'sum',
            'usd_amount': lambda x: x.sum() if x.notna().any() else None  # Custom agg to preserve NULL
        }).reset_index()
        usage_df = usage_df[['merchant_id', 'product', 'segment', 'event', 'date_id', 'count_of_events', 'usd_amount']]

        return merchants_df, products_df, events_df, dates_df, usage_df
    except Exception as e:
        logging.error(f'Transformation failed with erro: {e}')
        raise
    


def load(merchants_df, products_df, events_df, dates_df, usage_df, engine):
    """Load transformed data into the database"""
    logging.info('Loading data into database')

    # Truncate all tables to erase existing data (To simplify data reloading and proceed to analysis)
    with engine.begin() as connection:
        connection.execute(text("TRUNCATE TABLE Merchants, Products, Events, Dates, Product_Usage RESTART IDENTITY CASCADE;"))
        logging.info("All tables truncated successfully")
    
    try:
        #Load Merchants
        merchants_df.to_sql('merchants', engine, if_exists='append', index=False)

        # Load Products (omit product_id; let SERIAL generate it)
        products_df.to_sql('products', engine, if_exists='append', index=False)

        # Retrieve generated product_ids from Products AND Merge to get product_id into events_df
        products_with_id = pd.read_sql("SELECT product_id, product_name FROM Products", engine)
        events_df = events_df.merge(products_with_id, left_on='product', right_on='product_name', how='left')
        events_df = events_df[['event', 'product_id']].rename(columns={'event': 'event_name'})

        # Load Events (omit event_id; let SERIAL generate it)
        events_df.to_sql('events', engine, if_exists='append', index=False)
    
        # Retrieve generated event_ids from Events
        events_with_id = pd.read_sql(""" 
            SELECT e.event_id, e.event_name, e.product_id, p.product_name 
            FROM events e 
            INNER JOIN products p
            ON e.product_id = p.product_id""", engine)

        # Load Dates (omit date_id; but since date_id is VARCHAR PRIMARY KEY, we insert with it)
        dates_df.to_sql('dates', engine, if_exists='append', index=False)

        # Merge to get event_id and product_id into usage_df
        usage_df = usage_df.merge(events_with_id, left_on=['event', 'product'], right_on=['event_name', 'product_name'], how='left')
        usage_df = usage_df[['merchant_id', 'product_id', 'segment' , 'event_id', 'date_id', 'count_of_events', 'usd_amount']]

        # Load Product_Usage (omit usage_id; let SERIAL generate it)
        usage_df.to_sql('product_usage', engine, if_exists='append', index=False)
    except Exception as e:
        logging.error(f'Data loading failed with erro: {e}')
        raise
    
    logging.info("Data loaded successfully.")
    

def main():
    try:
        engine = create_engine('postgresql://postgres:423123@localhost:5433/stripe_db')
        segment_df, usage_df = extract()
        # print("usage_df columns:", usage_df.columns.tolist())
        # print("usage_df head:\n", usage_df.head())
        merchants_df, products_df, events_df, dates_df, usage_df = transform(segment_df, usage_df, engine)
        load(merchants_df, products_df, events_df, dates_df, usage_df, engine)
        engine.dispose()

        validate_completeness(engine)
        validate_integrity(engine)
        validate_types(engine)
        validate_foreign_keys(engine)
        validate_business_rules(engine)
        validate_event_completeness(engine)  # New validation

        logging.info('Successfully extracted, transformed, and loaded data!')
    except Exception as e:
        logging.error(f'Pipeline failed with erro: {e}')
    
if __name__ == "__main__":
    main()

