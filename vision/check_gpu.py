"""Check the actual CUDA runtime with a small, verified GPU computation."""
import json
import platform
import torch


def main():
    result = {
        'python': platform.python_version(),
        'torch': torch.__version__,
        'cuda_runtime': torch.version.cuda,
        'cuda_available': torch.cuda.is_available(),
    }
    if not result['cuda_available']:
        print(json.dumps(result, indent=2))
        raise SystemExit('CUDA no disponible. No continuar con inferencia GPU.')
    device = torch.device('cuda:0')
    props = torch.cuda.get_device_properties(device)
    with torch.inference_mode():
        matrix = torch.arange(256, dtype=torch.float32).reshape(16, 16)
        actual = matrix.to(device) @ matrix.to(device).T
        torch.cuda.synchronize()
        torch.testing.assert_close(actual.cpu(), matrix @ matrix.T)
    result.update(gpu=props.name, vram_mib=props.total_memory // (1024 ** 2),
                  computation_device=str(actual.device), computation_verified=True)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
