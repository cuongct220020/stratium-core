import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import requests

# 1. Academic Style
sns.set_theme(style="whitegrid")
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 12,
    "axes.labelsize": 14,
    "axes.titlesize": 16,
    "legend.fontsize": 12,
    "xtick.labelsize": 12,
    "ytick.labelsize": 12,
    "pdf.fonttype": 42             # Đảm bảo font được nhúng chuẩn vào file PDF
})

def plot_latency_chart():
    # 2. (Giả lập) Lấy dữ liệu từ Prometheus thông qua requests & pandas
    # response = requests.get('http://localhost:9090/api/v1/query', params={'query': 'engram_latency'})
    # df = pd.DataFrame(...)
    
    # Dữ liệu giả lập cho Thử nghiệm 1 (The Great Disconnect)
    data = {
        'Time (s)': [1-6],
        'Latency (ms)': [7-11] # Đỉnh 520ms là lúc đứt mạng -> chuyển Sovereign
    }
    df = pd.DataFrame(data)

    # 3. Vẽ biểu đồ bằng Seaborn
    plt.figure(figsize=(8, 5)) # Kích thước chuẩn cho 1 cột trong bài báo 2 cột
    ax = sns.lineplot(data=df, x='Time (s)', y='Latency (ms)', 
                      linewidth=2.5, color='#1f77b4', marker='o')

    # Thêm đường đánh dấu (Annotation) khoảnh khắc Ngắt mạch (Circuit Breaker)
    plt.axvline(x=25, color='red', linestyle='--', linewidth=1.5, label='Network Partition')
    plt.text(26, 400, 'Sovereign Fallback Triggered', color='red', fontsize=11)

    # 4. Tinh chỉnh trục và xuất file
    plt.title('FSM Detection Latency during Network Partition', pad=15)
    plt.xlabel('Time (Seconds)')
    plt.ylabel('End-to-End Latency (ms)')
    plt.legend(loc='upper right')
    plt.tight_layout()

    # XUẤT RA FILE PDF VECTOR (KHÔNG BỊ VỠ NÉT)
    plt.savefig('figure_detection_latency.pdf', format='pdf', dpi=300)
    print("Đã xuất biểu đồ ra file figure_detection_latency.pdf thành công!")

if __name__ == "__main__":
    plot_latency_chart()