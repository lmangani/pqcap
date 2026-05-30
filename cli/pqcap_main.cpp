#include "duckdb.hpp"
#include "duckdb/main/extension_helper.hpp"
#include "duckdb/main/extension/generated_extension_loader.hpp"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

int RunShell(int argc, const char **argv);

namespace {

void PrintHelp(const char *prog) {
	std::fprintf(stderr,
	             "pqcap — query pqcap captures with an embedded DuckDB engine\n"
	             "\n"
	             "Usage:\n"
	             "  %s query -c \"SQL\"              Run one SQL statement\n"
	             "  %s query -f query.sql            Run SQL from a file\n"
	             "  %s convert <in.pcap|pcapng> <out.pqcapng>\n"
	             "                                   Copy capture and embed searchable index\n"
	             "  %s shell [duckdb-shell-flags]    Interactive SQL session\n"
	             "  %s version                       Show engine and extension versions\n"
	             "  %s help                          Show this help\n"
	             "\n"
	             "Examples:\n"
	             "  %s query -c \"SELECT COUNT(*) FROM read_pqcap('demo.pqcapng')\"\n"
	             "  %s convert capture.pcapng indexed.pqcapng\n"
	             "  %s query -c \"SELECT * FROM read_pqcap_packets('demo.pqcapng') LIMIT 5\"\n"
	             "\n"
	             "Table functions: read_pqcap(), read_pqcap_packets()\n"
	             "Shorthand: SELECT * FROM 'file.pqcapng' (metadata) or 'file.pcapng' (packets)\n"
	             "Export: COPY (...) TO 'out.pcapng' (FORMAT pcapng, mode 'pqcap')\n"
	             "Index:  SELECT pqcap_embed_index('capture.pcapng')  -- features only, in-place\n",
	             prog, prog, prog, prog, prog, prog, prog, prog, prog);
}

void PrintVersion() {
	duckdb::DuckDB db(nullptr);
	duckdb::ExtensionHelper::LoadAllExtensions(db);
	std::printf("pqcap cli\n");
	std::printf("duckdb %s\n", duckdb::DuckDB::LibraryVersion());
	for (auto &ext : duckdb::LinkedExtensions()) {
		std::printf("extension %s (linked)\n", ext.c_str());
	}
}

std::string ReadFile(const std::string &path) {
	std::ifstream in(path);
	if (!in) {
		throw std::runtime_error("failed to open SQL file: " + path);
	}
	std::ostringstream out;
	out << in.rdbuf();
	return out.str();
}

std::string SqlEscape(const std::string &s) {
	std::string out;
	out.reserve(s.size());
	for (char c : s) {
		if (c == '\'') {
			out += "''";
		} else {
			out += c;
		}
	}
	return out;
}

int RunDuckDBSql(const std::string &sql) {
	try {
		duckdb::DuckDB db(nullptr);
		duckdb::ExtensionHelper::LoadAllExtensions(db);
		duckdb::Connection con(db);
		auto result = con.Query(sql);
		if (result->HasError()) {
			std::fprintf(stderr, "error: %s\n", result->GetError().c_str());
			return 1;
		}
		const auto rendered = result->ToString();
		if (!rendered.empty()) {
			std::fwrite(rendered.data(), 1, rendered.size(), stdout);
			if (rendered.back() != '\n') {
				std::fputc('\n', stdout);
			}
		}
	} catch (const std::exception &ex) {
		std::fprintf(stderr, "error: %s\n", ex.what());
		return 1;
	}
	return 0;
}

int RunQueryCommand(int argc, char **argv) {
	std::string sql;
	for (int i = 1; i < argc; i++) {
		if (std::strcmp(argv[i], "-c") == 0 || std::strcmp(argv[i], "--sql") == 0) {
			if (i + 1 >= argc) {
				std::fprintf(stderr, "error: missing SQL after %s\n", argv[i]);
				return 1;
			}
			sql = argv[++i];
		} else if (std::strcmp(argv[i], "-f") == 0 || std::strcmp(argv[i], "--file") == 0) {
			if (i + 1 >= argc) {
				std::fprintf(stderr, "error: missing path after %s\n", argv[i]);
				return 1;
			}
			try {
				sql = ReadFile(argv[++i]);
			} catch (const std::exception &ex) {
				std::fprintf(stderr, "error: %s\n", ex.what());
				return 1;
			}
		} else if (std::strcmp(argv[i], "-h") == 0 || std::strcmp(argv[i], "--help") == 0) {
			PrintHelp(argv[0]);
			return 0;
		} else {
			std::fprintf(stderr, "error: unknown query option: %s\n", argv[i]);
			return 1;
		}
	}

	if (sql.empty()) {
		std::fprintf(stderr, "error: provide SQL with -c or -f\n");
		return 1;
	}

	return RunDuckDBSql(sql);
}

int RunConvertCommand(int argc, char **argv) {
	if (argc < 3) {
		std::fprintf(stderr, "usage: %s convert <input.pcap|input.pcapng> <output.pqcapng>\n", argv[0]);
		return 1;
	}

	const std::string input = argv[1];
	const std::string output = argv[2];

	if (!std::filesystem::exists(input)) {
		std::fprintf(stderr, "error: input capture not found: %s\n", input.c_str());
		return 1;
	}

	const auto out_dir = std::filesystem::path(output).parent_path();
	if (!out_dir.empty()) {
		std::error_code ec;
		std::filesystem::create_directories(out_dir, ec);
		if (ec) {
			std::fprintf(stderr, "error: failed to create output directory: %s\n", ec.message().c_str());
			return 1;
		}
	}

	if (std::filesystem::exists(output)) {
		std::error_code ec;
		std::filesystem::remove(output, ec);
		if (ec) {
			std::fprintf(stderr, "error: failed to remove existing output: %s\n", ec.message().c_str());
			return 1;
		}
	}

	try {
		std::filesystem::copy(input, output, std::filesystem::copy_options::overwrite_existing);
	} catch (const std::exception &ex) {
		std::fprintf(stderr, "error: failed to copy capture: %s\n", ex.what());
		return 1;
	}

	const std::string sql =
	    "SELECT pqcap_embed_index('" + SqlEscape(output) + "')";

	std::fprintf(stderr, "indexing %s -> %s (packet features in parquet, payloads in capture)\n", input.c_str(),
	             output.c_str());
	return RunDuckDBSql(sql);
}

int RunShellCommand(int argc, char **argv) {
	std::vector<const char *> shell_argv;
	shell_argv.reserve(static_cast<size_t>(argc) + 1);
	shell_argv.push_back("pqcap");
	for (int i = 2; i < argc; i++) {
		shell_argv.push_back(argv[i]);
	}
	return RunShell(static_cast<int>(shell_argv.size()), shell_argv.data());
}

} // namespace

int main(int argc, char **argv) {
	if (argc < 2) {
		PrintHelp(argv[0]);
		return 0;
	}

	const std::string cmd = argv[1];
	if (cmd == "help" || cmd == "-h" || cmd == "--help") {
		PrintHelp(argv[0]);
		return 0;
	}
	if (cmd == "version" || cmd == "--version") {
		PrintVersion();
		return 0;
	}
	if (cmd == "query") {
		return RunQueryCommand(argc - 1, argv + 1);
	}
	if (cmd == "convert") {
		return RunConvertCommand(argc - 1, argv + 1);
	}
	if (cmd == "shell") {
		return RunShellCommand(argc, argv);
	}

	std::fprintf(stderr, "error: unknown command '%s'\n\n", cmd.c_str());
	PrintHelp(argv[0]);
	return 1;
}
