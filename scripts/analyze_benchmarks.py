from pathlib import Path
import statistics

def analyze_directory(directory):
    bitrates = []
    total_lost = 0
    total_sent = 0

    for path in sorted(directory.glob("run_*.txt")):
        print(f"Processing {path.name}")

        with path.open() as f:
            for line in f:
                if line.strip().endswith("receiver"):
                    x = line.split()

                    bitrate = float(x[6])

                    lost, total = x[10].split("/")
                    lost = int(lost)
                    total = int(total)

                    bitrates.append(bitrate)
                    total_lost += lost
                    total_sent += total
                    print(f"Bitrate = {bitrate} Gbps")
                    print(f"Lost = {lost}")
                    print(f"Total = {total}")


        print("\n")

    if len(bitrates) != 5:
        raise ValueError(f"Expected 5 results, found {len(bitrates)}")
    return {
        "mean": statistics.mean(bitrates),
        "median": statistics.median(bitrates),
        "std_dev": statistics.stdev(bitrates),
        "loss_percent": total_lost / total_sent * 100,
    }


linux = analyze_directory(Path("benchmarks/linux_1400"))
xdp = analyze_directory(Path("benchmarks/xdp_1400_repeat2"))

print("Linux:", linux)
print("XDP:", xdp)

difference = (
    (linux["mean"] - xdp["mean"])
    / xdp["mean"]
) * 100

print(f"Linux vs XDP throughput difference: {difference:.2f}%")