import os

inventory = [
    (
        os.environ.get("LAB_TARGET", ""),
        {
            "install_postgres": True,
            "concourse_web": True,
            "concourse_worker": True,
        },
    )
]
