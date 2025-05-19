import os

target = os.environ.get("LAB_TARGET", "")
if not target:
    raise ValueError("LAB_TARGET environment variable is not set")
print(f"TARGET: {target}")

inventory = [
    (
        target,
        {
            "install_kind": True,
        },
    )
]
