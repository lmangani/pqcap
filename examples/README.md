## Examples

### Build a demo pqcap file

```bash
bash examples/build_bundle_example.sh
```

Output:

- `.tmp/examples/demo.pqcapng`

### Query embedded metadata with DuckDB

```bash
bash scripts/pqcap_query.sh .tmp/examples/demo.pqcapng "protocols LIKE '%udp%'"
```

### Inspect capture with tshark

```bash
tshark -r .tmp/examples/demo.pqcapng -c 5
```
