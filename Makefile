.PHONY: test example validate extension-smoke release-check

test:
	bash tests/run_all.sh

example:
	bash examples/build_bundle_example.sh

validate:
	bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng

extension-smoke:
	bash tests/extension/smoke_build_and_query.sh

release-check:
	bash examples/build_bundle_example.sh
	bash scripts/pqcap_validate.sh .tmp/examples/demo.pqcapng
	bash tests/run_all.sh
	bash tests/extension/smoke_build_and_query.sh
