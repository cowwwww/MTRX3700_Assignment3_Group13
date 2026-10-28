# Round 2 verification evidence

Synthetic simulation and virtual-pin Quartus estimates only. No hardware run.
Latest full regression: PASS in 71.422 s; mutation CAUGHT.
Verilator exact 5.050: False. See test_results.json.

positive.log covers reduced units/integration; full_size_positive.log covers
default QVGA and complete VGA; translation_positive.log covers standalone SAD.
negative.log must fail on the intended inhibited-wheel assertion.
source_snapshot.json records current source/config hashes; test_results.json
records the compiled RTL/bench hashes. Quartus reports identify each top;
robot_system excludes the standalone translation kernel. Root evidence files
outside this round2 directory remain archived Round 1 evidence.
