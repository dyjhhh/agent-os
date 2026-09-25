.PHONY: scan test demo
test:
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s examples/continuity -p 'test_*.py' -v
	PYTHONDONTWRITEBYTECODE=1 python3 tools/test_sensitivity_scan.py
demo:
	PYTHONDONTWRITEBYTECODE=1 python3 examples/continuity/demo.py
scan:      ## fail if anything secret-shaped or personal-looking is in the tree
	bash tools/sensitivity-scan.sh
