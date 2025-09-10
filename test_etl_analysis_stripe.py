import pandas as pd
from sqlalchemy import create_engine, text
import logging
import pytest
from dm_etl_analysis_stripe import extract, transform, load
from unittest.mock import patch

@pytest.fixture(scope="module")
def setup_test_environment():
    # Test DB connection
    try:
        engine = create_engine('postgresql://postgres:423123@localhost:5433/test_stripe_db')
        with engine.begin() as connection:  # Use begin() context manager
            connection.execute(text("TRUNCATE TABLE Merchants, Products, Events, Dates, Product_Usage RESTART IDENTITY CASCADE;"))
        logging.info("Test DB reset successful")
    except Exception as e:
        logging.error(f"Test DB reset failed: {e}")
        raise

    # Mock data
    segment_df = pd.DataFrame({
        'merchant': [1, 2],
        'saas': [1, 0],
        'ecommerce': [0, 1],
        'platforms': [0, 1]
    })
    usage_df = pd.DataFrame({
        'merchant_id': [1, 2],
        'product': ['A', 'B'],
        'event': ['click', 'view'],
        'date': ['2023-01-01', '2023-01-02'],
        'count_of_events': [100, 200],
        'usd_amount': [1000, 2000]
    })

    yield {'engine': engine, 'segment_df': segment_df, 'usage_df': usage_df}

    # Teardown
    try:
        with engine.begin() as connection:  # Use begin() context manager
            connection.execute(text("TRUNCATE TABLE Merchants, Products, Events, Dates, Product_Usage RESTART IDENTITY CASCADE;"))
        logging.info("Test DB teardown successful")
    except Exception as e:
        logging.error(f"Test DB teardown failed: {e}")
    engine.dispose()


@pytest.fixture
def mock_extract_data(setup_test_environment):
    mock_segment_df = setup_test_environment['segment_df']
    mock_usage_df = setup_test_environment['usage_df']
    with patch('pandas.read_csv') as mock_read_csv:
        mock_read_csv.side_effect = [mock_segment_df, mock_usage_df]
        yield mock_segment_df, mock_usage_df

def test_extract(setup_test_environment, mock_extract_data):
    mock_segment_df, mock_usage_df = mock_extract_data
    segment_df, usage_df = extract(segment_file='mock_segment.csv', usage_file='mock_usage.csv')
    assert not segment_df.empty and not usage_df.empty
    logging.info("Extract test passed")

def test_extract_validation(setup_test_environment, mock_extract_data):
    mock_segment_df, mock_usage_df = mock_extract_data
    segment_df, usage_df = extract(segment_file='mock_segment.csv', usage_file='mock_usage.csv')
    
    # Check for no nulls
    assert segment_df.isnull().sum().sum() == 0, "Nulls in segment_df"
    assert usage_df.isnull().sum().sum() == 0, "Nulls in usage_df"

    # Check expected columns
    expected_segment_cols = ['merchant', 'saas', 'ecommerce', 'platforms']
    assert all(col in segment_df.columns for col in expected_segment_cols), "Missing columns in segment_df"

    expected_usage_cols = ['merchant_id', 'date', 'product', 'event', 'count_of_events', 'usd_amount']
    assert all(col in usage_df.columns for col in expected_usage_cols), "Missing columns in usage_df"

    # Check data types
    assert usage_df['count_of_events'].dtype == 'int64', "Incorrect type for count_of_events"

    logging.info("Extract data validation passed")


def test_transform(setup_test_environment):
    segment_df = setup_test_environment['segment_df']
    usage_df = setup_test_environment['usage_df']

    m_df, p_df, e_df, d_df, u_df = transform(segment_df, usage_df)
    assert 'merchant_id' in m_df.columns
    assert 'segment' in m_df.columns
    assert 'product' in u_df.columns
    assert 'segment' in u_df.columns

    logging.info("Transform test passed")


def test_load(setup_test_environment):
    segment_df = setup_test_environment['segment_df']
    usage_df = setup_test_environment['usage_df']
    engine = setup_test_environment['engine']
    try:
        m_df, p_df, e_df, d_df, u_df = transform(segment_df, usage_df)
        load(m_df, p_df, e_df, d_df, u_df, engine)
        result = pd.read_sql('SELECT * FROM Merchants', engine)
        assert not result.empty
        logging.info("Load test passed")
    except Exception as e:
        logging.error(f"Load test failed: {e}")
        raise

