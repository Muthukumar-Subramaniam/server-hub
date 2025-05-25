#!/bin/bash
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py --user
pip3 install packaging
pip3 install --user ansible
pip3 install argcomplete
activate-global-python-argcomplete
rm get-pip.py
