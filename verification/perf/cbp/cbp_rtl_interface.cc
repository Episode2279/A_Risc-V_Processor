#include "VCbpRtlPredictor.h"
#include "cbp.h"
#include "verilated.h"

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <optional>
#include <unordered_map>

namespace {

constexpr uint32_t kMetaSlotMask = 4095U;

struct PredictionContext {
    uint32_t rtl_pc = 0;
    uint16_t meta_slot = 0;
    bool final_prediction = false;
    bool raw_tage_prediction = false;
    bool pre_sc_prediction = false;
    bool provider_valid = false;
    bool loop_used = false;
    bool sc_low_confidence = false;
    bool actual_known = false;
    bool actual_taken = false;
    uint64_t next_pc = 0;
};

std::unique_ptr<VerilatedContext> context;
std::unique_ptr<VCbpRtlPredictor> dut;
std::unordered_map<uint64_t, PredictionContext> predictions;
std::unordered_map<uint64_t, uint64_t> known_taken_targets;

uint64_t internal_ticks = 0;
uint64_t conditional_predictions = 0;
uint64_t final_mispredictions = 0;
uint64_t raw_tage_mispredictions = 0;
uint64_t pre_sc_mispredictions = 0;
uint64_t sc_overrides = 0;
uint64_t sc_corrections = 0;
uint64_t sc_harms = 0;
uint64_t loop_overrides = 0;
uint64_t loop_corrections = 0;
uint64_t loop_harms = 0;

uint64_t unique_id(uint64_t seq_no, uint8_t piece)
{
    assert(piece < 16);
    return (seq_no << 4) | static_cast<uint64_t>(piece);
}

// CBP2025 traces use 64-bit virtual PCs, while this RV32 predictor hashes a
// 32-bit PC.  Fold the upper half into bits [31:2] and preserve instruction
// alignment explicitly.  This avoids silently discarding an address-space
// identifier while keeping the RTL interface unchanged.
uint32_t fold_pc(uint64_t pc)
{
    const uint32_t low = static_cast<uint32_t>(pc);
    const uint32_t high = static_cast<uint32_t>(pc >> 32);
    return ((low ^ high) & ~uint32_t{3}) | (low & uint32_t{3});
}

void clear_commands()
{
    dut->saveMetaValid_i = 0;
    dut->historyUpdateValid_i = 0;
    dut->historyConditional_i = 0;
    dut->historyTaken_i = 0;
    dut->historyBackward_i = 0;
    dut->commitValid_i = 0;
    dut->commitConditional_i = 0;
    dut->commitTaken_i = 0;
}

void tick()
{
    dut->clk = 0;
    dut->eval();
    context->timeInc(1);
    dut->clk = 1;
    dut->eval();
    context->timeInc(1);
    dut->clk = 0;
    dut->eval();
    context->timeInc(1);
    ++internal_ticks;
}

bool branch_is_backward(uint64_t pc, bool taken, uint64_t next_pc)
{
    if (taken) {
        known_taken_targets[pc] = next_pc;
        return next_pc < pc;
    }
    const auto target = known_taken_targets.find(pc);
    return target != known_taken_targets.end() && target->second < pc;
}

uint32_t synthetic_target(uint32_t rtl_pc, bool backward)
{
    return backward ? rtl_pc - uint32_t{4} : rtl_pc + uint32_t{4};
}

void wait_for_commit_port()
{
    clear_commands();
    while (!dut->commitReady_o)
        tick();
}

}  // namespace

void beginCondDirPredictor()
{
    context = std::make_unique<VerilatedContext>();
    dut = std::make_unique<VCbpRtlPredictor>(context.get());

    dut->clk = 0;
    dut->rst = 0;
    dut->queryPc_i = 0;
    dut->saveMetaSlot_i = 0;
    dut->commitMetaSlot_i = 0;
    dut->commitPc_i = 0;
    dut->commitTarget_i = 4;
    clear_commands();
    for (int cycle = 0; cycle < 4; ++cycle)
        tick();
    dut->rst = 1;
    tick();
}

void notify_instr_fetch(uint64_t, uint8_t, uint64_t, const uint64_t)
{
}

bool get_cond_dir_prediction(
    uint64_t seq_no,
    uint8_t piece,
    uint64_t pc,
    const uint64_t)
{
    const uint64_t id = unique_id(seq_no, piece);
    // A CBP sequence number identifies the dynamic instruction; piece only
    // distinguishes multiple micro-pieces of that same instruction.  A
    // conditional branch has one prediction-bearing piece, so index transient
    // metadata by seq_no directly.  With 4096 slots this safely exceeds the
    // official simulator's 1024-instruction window.  Masking unique_id here
    // would retain only eight seq_no bits because its low four bits are piece.
    const uint16_t slot = static_cast<uint16_t>(
        seq_no & static_cast<uint64_t>(kMetaSlotMask));

    clear_commands();
    dut->queryPc_i = fold_pc(pc);
    tick();

    PredictionContext saved;
    saved.rtl_pc = fold_pc(pc);
    saved.meta_slot = slot;
    saved.final_prediction = dut->prediction_o;
    saved.raw_tage_prediction = dut->rawTagePrediction_o;
    saved.pre_sc_prediction = dut->preScPrediction_o;
    saved.provider_valid = dut->providerValid_o;
    saved.loop_used = dut->loopUsed_o;
    saved.sc_low_confidence = dut->scLowConfidence_o;
    predictions[id] = saved;

    dut->saveMetaValid_i = 1;
    dut->saveMetaSlot_i = slot;
    tick();
    clear_commands();

    ++conditional_predictions;
    return saved.final_prediction;
}

void spec_update(
    uint64_t seq_no,
    uint8_t piece,
    uint64_t pc,
    InstClass inst_class,
    const bool resolve_dir,
    const bool,
    const uint64_t next_pc)
{
    assert(is_br(inst_class));

    if (is_cond_br(inst_class)) {
        const uint64_t id = unique_id(seq_no, piece);
        auto found = predictions.find(id);
        assert(found != predictions.end());
        found->second.actual_known = true;
        found->second.actual_taken = resolve_dir;
        found->second.next_pc = next_pc;
    } else {
        // get_cond_dir_prediction is not called for unconditional control
        // flow.  Prime predictionPc so Path History hashes the correct PC.
        clear_commands();
        dut->queryPc_i = fold_pc(pc);
        tick();
    }

    clear_commands();
    dut->historyUpdateValid_i = 1;
    dut->historyConditional_i = is_cond_br(inst_class);
    dut->historyTaken_i = resolve_dir;
    dut->historyBackward_i =
        is_cond_br(inst_class) &&
        branch_is_backward(pc, resolve_dir, next_pc);
    tick();
    clear_commands();
}

void notify_instr_decode(
    uint64_t,
    uint8_t,
    uint64_t,
    const DecodeInfo&,
    const uint64_t)
{
}

void notify_agen_complete(
    uint64_t,
    uint8_t,
    uint64_t,
    const DecodeInfo&,
    const uint64_t,
    const uint64_t,
    const uint64_t)
{
}

void notify_instr_execute_resolve(
    uint64_t seq_no,
    uint8_t piece,
    uint64_t pc,
    const bool,
    const ExecuteInfo& exec_info,
    const uint64_t)
{
    if (!is_cond_br(exec_info.dec_info.insn_class))
        return;

    const uint64_t id = unique_id(seq_no, piece);
    auto found = predictions.find(id);
    assert(found != predictions.end());
    found->second.actual_known = true;
    found->second.actual_taken = exec_info.taken.value();
    found->second.next_pc = exec_info.next_pc;
    if (exec_info.taken_target.has_value())
        known_taken_targets[pc] = exec_info.taken_target.value();
}

void notify_instr_commit(
    uint64_t seq_no,
    uint8_t piece,
    uint64_t pc,
    const bool,
    const ExecuteInfo& exec_info,
    const uint64_t)
{
    if (!is_br(exec_info.dec_info.insn_class))
        return;

    const bool conditional = is_cond_br(exec_info.dec_info.insn_class);
    const bool actual_taken =
        conditional ? exec_info.taken.value() : true;
    const uint64_t actual_target =
        exec_info.taken_target.value_or(exec_info.next_pc);
    const bool backward =
        conditional && (actual_target < pc);
    if (conditional && exec_info.taken_target.has_value())
        known_taken_targets[pc] = actual_target;

    uint16_t slot = 0;
    if (conditional) {
        const uint64_t id = unique_id(seq_no, piece);
        auto found = predictions.find(id);
        assert(found != predictions.end());
        PredictionContext& saved = found->second;
        assert(saved.actual_known);
        slot = saved.meta_slot;

        final_mispredictions +=
            saved.final_prediction != actual_taken;
        raw_tage_mispredictions +=
            saved.raw_tage_prediction != actual_taken;
        pre_sc_mispredictions +=
            saved.pre_sc_prediction != actual_taken;

        if (saved.final_prediction != saved.pre_sc_prediction) {
            ++sc_overrides;
            if (saved.final_prediction == actual_taken)
                ++sc_corrections;
            else
                ++sc_harms;
        }
        if (saved.pre_sc_prediction != saved.raw_tage_prediction) {
            ++loop_overrides;
            if (saved.pre_sc_prediction == actual_taken)
                ++loop_corrections;
            else
                ++loop_harms;
        }
    }

    wait_for_commit_port();
    dut->commitValid_i = 1;
    dut->commitConditional_i = conditional;
    dut->commitMetaSlot_i = slot;
    dut->commitPc_i = fold_pc(pc);
    dut->commitTarget_i =
        synthetic_target(fold_pc(pc), backward);
    dut->commitTaken_i = actual_taken;
    tick();
    clear_commands();
    // The production four-entry update queue trains on its dequeue edge.
    tick();

    if (conditional)
        predictions.erase(unique_id(seq_no, piece));
}

void endCondDirPredictor()
{
    clear_commands();
    for (int drain = 0; drain < 8; ++drain)
        tick();

    std::printf(
        "RTL_CBP full_conditional=%llu final_misp=%llu "
        "raw_tage_misp=%llu pre_sc_misp=%llu internal_ticks=%llu\n",
        static_cast<unsigned long long>(conditional_predictions),
        static_cast<unsigned long long>(final_mispredictions),
        static_cast<unsigned long long>(raw_tage_mispredictions),
        static_cast<unsigned long long>(pre_sc_mispredictions),
        static_cast<unsigned long long>(internal_ticks));
    std::printf(
        "RTL_CBP_SC overrides=%llu corrections=%llu harms=%llu net=%lld\n",
        static_cast<unsigned long long>(sc_overrides),
        static_cast<unsigned long long>(sc_corrections),
        static_cast<unsigned long long>(sc_harms),
        static_cast<long long>(sc_corrections) -
            static_cast<long long>(sc_harms));
    std::printf(
        "RTL_CBP_LOOP overrides=%llu corrections=%llu harms=%llu net=%lld\n",
        static_cast<unsigned long long>(loop_overrides),
        static_cast<unsigned long long>(loop_corrections),
        static_cast<unsigned long long>(loop_harms),
        static_cast<long long>(loop_corrections) -
            static_cast<long long>(loop_harms));

    dut->final();
    dut.reset();
    context.reset();
}
