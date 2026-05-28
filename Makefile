.PHONY: test example validate release-check

test:
	bash tests/run_all.sh

example:
	bash examples/build_bundle_example.sh

validate:
	bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng

release-check:
	bash examples/build_bundle_example.sh
	bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng
	bash tests/run_all.sh
