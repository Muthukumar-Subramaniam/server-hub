#!/bin/bash
#----------------------------------------------------------------------------------------#
# If you encounter any issues with this script, or have suggestions or feature requests, #
# please open an issue at: https://github.com/Muthukumar-Subramaniam/server-hub/issues   #
#----------------------------------------------------------------------------------------#
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py --user
pip3 install --user packaging
pip3 install --user ansible
pip3 install --user argcomplete
if command -v activate-global-python-argcomplete &>/dev/null; then
	activate-global-python-argcomplete --user || true
fi
rm get-pip.py
