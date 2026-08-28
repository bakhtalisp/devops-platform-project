import time
import os

def main():
    print("worker-service started, waiting for api-service dependency...", flush=True)
    while True:
        print("worker-service: doing background task...", flush=True)
        time.sleep(10)

if __name__ == "__main__":
    main()
