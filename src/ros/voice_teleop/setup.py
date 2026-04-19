from setuptools import find_packages, setup

package_name = "voice_teleop"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Naoki Shibahara",
    maintainer_email="n.shiba0101@gmail.com",
    description="Voice-driven teleop for Go2 via Parakeet or Azure Speech STT.",
    license="BSD-3-Clause",
    entry_points={
        "console_scripts": [
            "voice_teleop = voice_teleop.node:main",
        ],
    },
)
