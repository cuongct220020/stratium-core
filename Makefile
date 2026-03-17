TLA_TOOLS_URL=https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
TLA_JAR=spec/tla2tools.jar

$(TLA_JAR):
	@echo "Downloading TLA+ tools..."
	curl -L -o $(TLA_JAR) $(TLA_TOOLS_URL)


verify-fsm: $(TLA_JAR)
	@echo "Running TLC Model Checker on EngramFSM..."
	cd spec && java -jar tla2tools.jar -modelcheck -config EngramFSM.cfg EngramFSM.tla