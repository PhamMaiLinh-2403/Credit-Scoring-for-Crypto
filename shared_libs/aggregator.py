# shared_libs/aggregator.py

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
        return aggregated_model
