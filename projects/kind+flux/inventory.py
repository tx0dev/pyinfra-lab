import os

inventory = [
    (
        os.environ.get("LAB_TARGET", ""),
        {
            "install_kind": True,
        },
    )
]
