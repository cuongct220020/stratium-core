import requests
import matplotlib.pyplot as plt
import seaborn as sns
import subprocess
import time
from typing import Dict, Any, List

# ==========================================
# 1. CONSTANTS & FSM PARAMETERS FROM THE PAPER
# ==========================================
# Anchor Gap (Delta H) thresholds to trigger FSM transitions
THRESHOLD_SUSPICIOUS = 100
THRESHOLD_SOVEREIGN = 500

PROMETHEUS_URL = 'http://localhost:9090/api/v1/query_range'

# ==========================================
# 2. STANDARD ACADEMIC PLOT CONFIGURATION (IEEE/ACM)
# ==========================================
def setup_academic_plot_style():
    """Set up matplotlib formatting for academic papers (Vector PDF)."""
    sns.set_theme(style="whitegrid")
    plt.rcParams.update({
        "font.family": "serif",
        "font.size": 12,
        "axes.labelsize": 14,
        "axes.titlesize": 16,
        "legend.fontsize": 12,
        "xtick.labelsize": 12,
        "ytick.labelsize": 12,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "lines.linewidth": 2.5
    })

# ==========================================
# 3. PROMETHEUS DATA FETCHING
# ==========================================
def fetch_prometheus_metric(query: str, start_time: float, end_time: float, step: str = '1s') -> List[Dict]:
    """
    Query time-series data from Prometheus (e.g., T_DA or Throughput).
    Returns a list of timestamps and values to be used in a Pandas DataFrame.
    """
    params = {
        'query': query,
        'start': start_time,
        'end': end_time,
        'step': step
    }

    try:
        response = requests.get(PROMETHEUS_URL, params=params)
        response.raise_for_status()
        data = response.json()['data']['result']
        if not data:
            print(f"Warning: No data found for query '{query}'.")
            return []

        # Extract the first data stream
        values = data[0]['values']
        return [{"timestamp": float(v[0]), "value": float(v[1])} for v in values]

    except Exception as e:
        print(f"Error querying Prometheus: {e}")
        return []

# ==========================================
# 4. CHAOS ENGINEERING TOOLS (NETWORK FAULT SIMULATION)
# ==========================================
def disconnect_container_from_network(container_name: str, network_name: str = 'engram_net'):
    """
    Simulate a network partition or Eclipse Attack scenario.
    """
    print(f"[{time.strftime('%X')}] Disconnecting {container_name} from network {network_name}...")
    cmd = f"docker network disconnect {network_name} {container_name}"
    subprocess.run(cmd, shell=True, check=False, capture_output=True)

def reconnect_container_to_network(container_name: str, network_name: str = 'engram_net'):
    """
    Restore network connection to evaluate Re-anchoring and Recovery Time.
    """
    print(f"[{time.strftime('%X')}] Reconnecting {container_name} to network {network_name}...")
    cmd = f"docker network connect {network_name} {container_name}"
    subprocess.run(cmd, shell=True, check=False, capture_output=True)

def simulate_network_delay(container_name: str, delay_ms: int = 500, jitter_ms: int = 50):
    """
    Inject random delay (Jitter) using Linux NetEm (tc).
    Used to simulate increased DA Latency (T_DA).
    """
    print(f"[{time.strftime('%X')}] Injecting {delay_ms}ms delay (±{jitter_ms}ms) into {container_name}...")
    cmd = f"docker exec --privileged {container_name} tc qdisc add dev eth0 root netem delay {delay_ms}ms {jitter_ms}ms"
    subprocess.run(cmd, shell=True, check=False, capture_output=True)

def remove_network_delay(container_name: str):
    """Remove injected delay from the container."""
    cmd = f"docker exec --privileged {container_name} tc qdisc del dev eth0 root"
    subprocess.run(cmd, shell=True, check=False, capture_output=True)