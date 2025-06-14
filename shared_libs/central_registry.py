# shared_libs/central_registry.py

class CentralRegistry:
    """
    Manages the registration and state of active Swarm Nodes.
    The Coordinator uses this registry to keep track of participating nodes.
    """
    def __init__(self):
        self._registered_nodes = {} # Stores node_id: {"endpoint": url, "status": "active"}
        print("CentralRegistry initialized.")

    def register_node(self, node_id: str, endpoint_url: str):
        """
        Registers a new Swarm Node or updates an existing one.
        """
        self._registered_nodes[node_id] = {"endpoint": endpoint_url, "status": "active"}
        print(f"Registry: Node '{node_id}' registered/updated with endpoint {endpoint_url}")

    def get_registered_nodes(self) -> dict:
        """
        Returns a dictionary of all currently registered and active nodes.
        """
        # In a more complex scenario, you might filter by 'active' status
        return self._registered_nodes

    def remove_node(self, node_id: str):
        """
        Removes a node from the registry (e.g., if it goes offline).
        """
        if node_id in self._registered_nodes:
            del self._registered_nodes[node_id]
            print(f"Registry: Node '{node_id}' removed.")
        else:
            print(f"Registry: Node '{node_id}' not found for removal.")

    def update_node_status(self, node_id: str, status: str):
        """
        Updates the status of a registered node.
        """
        if node_id in self._registered_nodes:
            self._registered_nodes[node_id]["status"] = status
            print(f"Registry: Node '{node_id}' status updated to '{status}'.")
        else:
            print(f"Registry: Node '{node_id}' not found for status update.")