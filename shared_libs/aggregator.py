import pandas as pd
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error
import numpy as np
import boto3
from io import BytesIO  # Để đọc dữ liệu từ S3 mà không cần lưu trực tiếp vào đĩa

class Aggregator:
    """
    Handles the aggregation of model parameters received from multiple Swarm Nodes.
    """
    def __init__(self):
        print("Aggregator initialized.")

    def aggregate_models(self, local_model_params_list) -> dict:
        """
        Aggregates a list of local model parameters into a single global model.
        For each feature, it averages coefficients only across the models that have that feature.
        """
        if not local_model_params_list:
            raise ValueError("Cannot aggregate an empty list of models.")

        aggregated_coef = {}
        coef_counts = {}
        aggregated_intercept = 0.0

        for model_params in local_model_params_list:
            for key, value in model_params['coef'].items():
                if key not in aggregated_coef:
                    aggregated_coef[key] = 0.0
                    coef_counts[key] = 0
                aggregated_coef[key] += value
                coef_counts[key] += 1
            aggregated_intercept += model_params['intercept']

        for key in aggregated_coef:
            aggregated_coef[key] /= coef_counts[key]
        aggregated_intercept /= len(local_model_params_list)

        aggregated_model = {
            'coef': aggregated_coef,
            'intercept': aggregated_intercept
        }

        print(f"Aggregator: Successfully aggregated {len(local_model_params_list)} models.")
        print(self.test_accuracy(aggregated_model))  # Test the accuracy after aggregation
        return aggregated_model
    
    def test_accuracy(self, params):
        """Test the aggregated model on test data from S3."""
        s3_bucket_name = os.environ.get('S3_BUCKET_NAME', 'durian-bucket-titan')  # Sử dụng tên bucket từ biến môi trường
        s3_key = 'data/test.parquet'  # Đảm bảo key đúng

        print(f"Aggregator: Loading test data from S3://{s3_bucket_name}/{s3_key}...")

        try:
            s3 = boto3.client('s3')
            obj = s3.get_object(Bucket=s3_bucket_name, Key=s3_key)
            with BytesIO(obj['Body'].read()) as data_buffer:
                test_df = pd.read_parquet(data_buffer)
            print(f"Aggregator: Successfully loaded test data from S3.")
        except Exception as e:
            print(f"Aggregator: ERROR loading test data from S3: {e}")
            return "Error loading data from S3"

        test_X = test_df.drop(columns=['Target'])
        test_y = test_df['Target']
        feature_set = test_X.columns.tolist()

        model = SGDRegressor(
            loss='squared_error',
            penalty=None, alpha=0.0001,
            max_iter=1, tol=None,
            learning_rate='constant', eta0=0.01,
            random_state=42 # for reproducibility
        )

        # Warm-up fit to avoid assignment error
        model.partial_fit(test_X[:1], test_y[:1])

        # Prepare initial parameters for SGDRegressor from our dict format
        # Ensure order matches self.X.columns
        initial_coef = np.array([params['coef'][f] for f in feature_set])
        initial_intercept = np.array([params['intercept']])

        # partial_fit requires initial_coef and initial_intercept set directly
        model.coef_ = initial_coef
        model.intercept_ = initial_intercept

        predictions = model.predict(test_X)
        mse = mean_squared_error(test_y, predictions)
        return f'Accuracy (MSE): {mse}'
