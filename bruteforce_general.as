// constants
const array<string> targetNames = { "finish", "cp", "trigger" };

Manager @m_Manager;

// bruteforce vars
int m_bestTime; // best time the bf found so far, precise or not

// settings vars
string m_resultFileName;

string m_target;

bool m_usePreciseTime;
uint64 m_preciseTimePrecision;

uint m_modifySteeringMinTime;
uint m_modifyAccelerationMinTime;
uint m_modifyBrakeMinTime;
uint m_modifySteeringMaxTime;
uint m_modifyAccelerationMaxTime;
uint m_modifyBrakeMaxTime;

uint m_modifySteeringMinCount;
uint m_modifyAccelerationMinCount;
uint m_modifyBrakeMinCount;
uint m_modifySteeringMaxCount;
uint m_modifyAccelerationMaxCount;
uint m_modifyBrakeMaxCount;

uint m_modifySteeringMinHoldTime;
uint m_modifyAccelerationMinHoldTime;
uint m_modifyBrakeMinHoldTime;
uint m_modifySteeringMaxHoldTime;
uint m_modifyAccelerationMaxHoldTime;
uint m_modifyBrakeMaxHoldTime;

uint m_modifySteeringMinDiff;
uint m_modifySteeringMaxDiff;

// TODO: implement
// bool m_modifyOnlyExistingInputs;

bool m_useFillMissingInputsSteering;
bool m_useFillMissingInputsAcceleration;
bool m_useFillMissingInputsBrake;

// todo: make the typing of this var less not good
double m_customStopTimeDelta;

bool m_useInfoLogging;
bool m_useIterLogging;

// info vars
uint m_iterations = 0; // total iterations
uint m_iterationsCounter = 0; // iterations counter, used to update the iterations per second
float m_iterationsPerSecond = 0.0f; // iterations per second
float m_lastIterationsPerSecondUpdate = 0.0f; // last time the iterations per second were updated


// helper functions
string DecimalFormatted(float number, int precision = 10) {
    return Text::FormatFloat(number, "{0:10f}", 0, precision);
}
string DecimalFormatted(double number, int precision = 10) {
    return Text::FormatFloat(number, "{0:10f}", 0, precision);
}

namespace NormalFin {
    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        bool raceFinished = simManager.PlayerInfo.RaceFinished;
        int tickTime = simManager.TickTime;

        if (raceFinished || (tickTime > (m_customStopTimeDelta != 0.0 ? (int(m_customStopTimeDelta) + m_bestTime) : m_bestTime))) {
            response.Decision = BFEvaluationDecision::Accept;
            return;
        }
    }

    void HandleSearchPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        int tickTime = simManager.TickTime;
        bool raceFinished = simManager.PlayerInfo.RaceFinished;

        if (raceFinished) {
            if (tickTime > (m_customStopTimeDelta != 0.0 ? (int(m_customStopTimeDelta) + m_bestTime) : m_bestTime)) {
                response.Decision = BFEvaluationDecision::Reject;
                return;
            }

            int newTime = tickTime - 10;

            string message = "Found";
            // im just explicitly doing the if check against m_customStopTimeDelta to make more clear what is going on
            if (m_customStopTimeDelta == 0.0) {
                message += " lower time: " + Text::FormatInt(newTime);
            } else {
                if (newTime < m_bestTime) {
                    message += " lower ";
                } else if (newTime == m_bestTime) {
                    message += " equal ";
                } else {
                    message += " higher ";
                }
                message += "time: " + Text::FormatInt(newTime);
            }

            m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + newTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
            
            m_bestTime = newTime;
            print(message, Severity::Success);
            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        if (tickTime > (m_customStopTimeDelta != 0.0 ? (int(m_customStopTimeDelta) + m_bestTime) : int(m_bestTime))) {
            response.Decision = BFEvaluationDecision::Reject;
            return;
        }
    }
}

namespace PreciseFin {
    double bestPreciseTime; // best precise time the bf found so far
    bool isEstimating = false;
    uint64 coeffMin = 0;
    uint64 coeffMax = 18446744073709551615; 
    SimulationState@ originalStateBeforeFinish;

    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        bool raceFinished = simManager.PlayerInfo.RaceFinished;
        int tickTime = simManager.TickTime;

        if (raceFinished || (tickTime > (m_customStopTimeDelta != 0.0 ? (int(m_customStopTimeDelta) + m_bestTime) : m_bestTime))) {
            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        response.Decision = BFEvaluationDecision::DoNothing;
    }

    void HandleSearchPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        bool raceFinished = simManager.PlayerInfo.RaceFinished;
        int tickTime = simManager.TickTime;

        if (!PreciseFin::isEstimating) {
            if (!raceFinished) {
                if (tickTime > (m_customStopTimeDelta != 0.0 ? (int(m_customStopTimeDelta) + m_bestTime) : m_bestTime)) {
                    response.Decision = BFEvaluationDecision::Reject;
                    return;
                }

                @PreciseFin::originalStateBeforeFinish = simManager.SaveState();
                response.Decision = BFEvaluationDecision::DoNothing;
                return;
            } else {
                PreciseFin::isEstimating = true;
            }
        } else {
            if (raceFinished) {
                PreciseFin::coeffMax = PreciseFin::coeffMin + (PreciseFin::coeffMax - PreciseFin::coeffMin) / 2;
            } else {
                PreciseFin::coeffMin = PreciseFin::coeffMin + (PreciseFin::coeffMax - PreciseFin::coeffMin) / 2;
            }
        }

        simManager.RewindToState(PreciseFin::originalStateBeforeFinish);
        
        uint64 currentCoeff = PreciseFin::coeffMin + (PreciseFin::coeffMax - PreciseFin::coeffMin) / 2;
        double currentCoeffPercentage = currentCoeff / 18446744073709551615.0;

        if (PreciseFin::coeffMax - PreciseFin::coeffMin > m_preciseTimePrecision) {
            vec3 LinearSpeed = simManager.Dyna.CurrentState.LinearSpeed;
            vec3 AngularSpeed = simManager.Dyna.CurrentState.AngularSpeed;
            LinearSpeed *= currentCoeffPercentage;
            AngularSpeed *= currentCoeffPercentage;
            simManager.Dyna.CurrentState.LinearSpeed = LinearSpeed;
            simManager.Dyna.CurrentState.AngularSpeed = AngularSpeed;
            response.Decision = BFEvaluationDecision::DoNothing;
            return;
        }

        // finished estimating precise time
        PreciseFin::isEstimating = false;
        PreciseFin::coeffMin = 0;
        PreciseFin::coeffMax = 18446744073709551615;

        double preciseTime = (simManager.RaceTime / 1000.0) + (currentCoeffPercentage / 100.0);
        double previousTime = PreciseFin::bestPreciseTime;

        if (preciseTime >= (m_customStopTimeDelta > 0.0 ? (previousTime + (m_customStopTimeDelta / 1000.0)) : previousTime)) {
            response.Decision = BFEvaluationDecision::Reject;
            return;
        }

        PreciseFin::bestPreciseTime = preciseTime;
        m_bestTime = int(Math::Floor(PreciseFin::bestPreciseTime * 100.0)) * 10;

        string message = "Found";
        // im just explicitly doing the if check against m_customStopTimeDelta to make more clear what is going on
        if (m_customStopTimeDelta == 0.0) {
            message += " lower precise time: " + DecimalFormatted(preciseTime, 16);
        } else {
            if (preciseTime < previousTime) {
                message += " lower ";
            } else if (preciseTime == previousTime) {
                message += " equal ";
            } else {
                message += " higher ";
            }
            message += "precise time: " + DecimalFormatted(preciseTime, 16);
        }
        
        m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)

        print(message, Severity::Success);
        response.Decision = BFEvaluationDecision::Accept;
    }
}

// variables that bruteforce needs to work and cannot be changed during simulation
void SetBruteforceVariables() {
    SimulationManager@ simManager = m_Manager.m_simManager;

    // General Variables
    m_bestTime = simManager.EventsDuration; // original time of the replay

    m_iterations = 0;
    m_iterationsCounter = 0;
    m_iterationsPerSecond = 0.0f;
    m_lastIterationsPerSecondUpdate = 0.0f;

    // PreciseFin Variables
    PreciseFin::isEstimating = false;
    PreciseFin::coeffMin = 0;
    PreciseFin::coeffMax = 18446744073709551615;
    PreciseFin::bestPreciseTime = double(m_bestTime + 10) / 1000.0; // best precise time the bf found so far

    // Bruteforce Variables
    m_resultFileName = GetVariableString("kim_bf_result_file_name");

    m_target = GetVariableString("kim_bf_target");

    m_useFillMissingInputsSteering = GetVariableBool("kim_bf_use_fill_missing_inputs_steering");
    m_useFillMissingInputsAcceleration = GetVariableBool("kim_bf_use_fill_missing_inputs_acceleration");
    m_useFillMissingInputsBrake = GetVariableBool("kim_bf_use_fill_missing_inputs_brake");
    
    m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
}

// settings that can be changed during simulation
void UpdateSettings() {
    SimulationManager@ simManager = m_Manager.m_simManager;

    // precise time
    m_usePreciseTime = GetVariableBool("kim_bf_use_precise_time");
	if (m_usePreciseTime) {
		// precise time precision
		m_preciseTimePrecision = uint(Math::Max(1, int(GetVariableDouble("kim_bf_precise_time_precision"))));
        SetVariable("kim_bf_precise_time_precision", m_preciseTimePrecision);
	}

    // input modification time range
    m_modifySteeringMinTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_min_time"))));
    m_modifySteeringMaxTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_max_time"))));
    m_modifySteeringMinTime = Math::Min(m_modifySteeringMinTime, m_modifySteeringMaxTime);
    SetVariable("kim_bf_modify_steering_min_time", m_modifySteeringMinTime);
    SetVariable("kim_bf_modify_steering_max_time", m_modifySteeringMaxTime);

    m_modifyAccelerationMinTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_min_time"))));
    m_modifyAccelerationMaxTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_max_time"))));
    m_modifyAccelerationMinTime = Math::Min(m_modifyAccelerationMinTime, m_modifyAccelerationMaxTime);
    SetVariable("kim_bf_modify_acceleration_min_time", m_modifyAccelerationMinTime);
    SetVariable("kim_bf_modify_acceleration_max_time", m_modifyAccelerationMaxTime);

    m_modifyBrakeMinTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_min_time"))));
    m_modifyBrakeMaxTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_max_time"))));
    m_modifyBrakeMinTime = Math::Min(m_modifyBrakeMinTime, m_modifyBrakeMaxTime);
    SetVariable("kim_bf_modify_brake_min_time", m_modifyBrakeMinTime);
    SetVariable("kim_bf_modify_brake_max_time", m_modifyBrakeMaxTime);

    // input modifications amount
	m_modifySteeringMinCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_min_count"))));
    m_modifySteeringMaxCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_max_count"))));
    m_modifySteeringMinCount = Math::Min(m_modifySteeringMinCount, m_modifySteeringMaxCount);
    SetVariable("kim_bf_modify_steering_min_count", m_modifySteeringMinCount);
    SetVariable("kim_bf_modify_steering_max_count", m_modifySteeringMaxCount);

    m_modifyAccelerationMinCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_min_count"))));
    m_modifyAccelerationMaxCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_max_count"))));
    m_modifyAccelerationMinCount = Math::Min(m_modifyAccelerationMinCount, m_modifyAccelerationMaxCount);
    SetVariable("kim_bf_modify_acceleration_min_count", m_modifyAccelerationMinCount);
    SetVariable("kim_bf_modify_acceleration_max_count", m_modifyAccelerationMaxCount);

    m_modifyBrakeMinCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_min_count"))));
    m_modifyBrakeMaxCount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_max_count"))));
    m_modifyBrakeMinCount = Math::Min(m_modifyBrakeMinCount, m_modifyBrakeMaxCount);
    SetVariable("kim_bf_modify_brake_min_count", m_modifyBrakeMinCount);
    SetVariable("kim_bf_modify_brake_max_count", m_modifyBrakeMaxCount);

    // hold times
    m_modifySteeringMinHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_min_hold_time"))));
    m_modifySteeringMaxHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_max_hold_time"))));
    m_modifySteeringMinHoldTime = Math::Min(m_modifySteeringMinHoldTime, m_modifySteeringMaxHoldTime);
    SetVariable("kim_bf_modify_steering_min_hold_time", m_modifySteeringMinHoldTime);
    SetVariable("kim_bf_modify_steering_max_hold_time", m_modifySteeringMaxHoldTime);

    m_modifyAccelerationMinHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_min_hold_time"))));
    m_modifyAccelerationMaxHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_max_hold_time"))));
    m_modifyAccelerationMinHoldTime = Math::Min(m_modifyAccelerationMinHoldTime, m_modifyAccelerationMaxHoldTime);
    SetVariable("kim_bf_modify_acceleration_min_hold_time", m_modifyAccelerationMinHoldTime);
    SetVariable("kim_bf_modify_acceleration_max_hold_time", m_modifyAccelerationMaxHoldTime);

    m_modifyBrakeMinHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_min_hold_time"))));
    m_modifyBrakeMaxHoldTime = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_max_hold_time"))));
    m_modifyBrakeMinHoldTime = Math::Min(m_modifyBrakeMinHoldTime, m_modifyBrakeMaxHoldTime);
    SetVariable("kim_bf_modify_brake_min_hold_time", m_modifyBrakeMinHoldTime);
    SetVariable("kim_bf_modify_brake_max_hold_time", m_modifyBrakeMaxHoldTime);

    // steering diff
	m_modifySteeringMinDiff = uint(Math::Clamp(int(GetVariableDouble("kim_bf_modify_steering_min_diff")), 1, 131072));
    m_modifySteeringMaxDiff = uint(Math::Clamp(int(GetVariableDouble("kim_bf_modify_steering_max_diff")), 1, 131072));
    m_modifySteeringMinDiff = Math::Min(m_modifySteeringMinDiff, m_modifySteeringMaxDiff);
    SetVariable("kim_bf_modify_steering_min_diff", m_modifySteeringMinDiff);
    SetVariable("kim_bf_modify_steering_max_diff", m_modifySteeringMaxDiff);

    // TODO: implement
    // modify only existing inputs
    // m_modifyOnlyExistingInputs = GetVariableBool("kim_bf_modify_only_existing_inputs");

    // custom stop time delta
    m_customStopTimeDelta = GetVariableDouble("kim_bf_custom_stop_time_delta");
	if (!m_usePreciseTime) {
		m_customStopTimeDelta = double(Math::Round(m_customStopTimeDelta * 100.0) * 10.0);
	} else {
		m_customStopTimeDelta = double(m_customStopTimeDelta * 1000.0);
	}

    if (@simManager != null && m_Manager.m_controller.active) {
        m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
    }

    // logging
    m_useInfoLogging = GetVariableBool("kim_bf_use_info_logging");
    m_useIterLogging = GetVariableBool("kim_bf_use_iter_logging");
}

/* SIMULATION MANAGEMENT */

class BruteforceController {
    BruteforceController() {}
    ~BruteforceController() {}

    
    void StartInitialPhase() {
        UpdateIterationsPerSecond(); // it aint really an iteration, but it kinda wont update the performance of the simulation if you happen to have a lot of initial phases

        m_phase = BFPhase::Initial;
        m_simManager.RewindToState(m_originalSimulationStates[m_rewindIndex]);
        m_originalSimulationStates.Resize(m_rewindIndex + 1);
    }

    void StartSearchPhase() {
        UpdateIterationsPerSecond();

        m_phase = BFPhase::Search;

        RandomNeighbour();
        m_simManager.RewindToState(m_originalSimulationStates[m_rewindIndex]);
    }

    void StartNewIteration() {
        UpdateIterationsPerSecond();

        // randomize the inputbuffers values
        RandomNeighbour();
        m_simManager.RewindToState(m_originalSimulationStates[m_rewindIndex]);
    }

    void OnSimulationBegin(SimulationManager@ simManager) {
        active = GetVariableString("controller") == "kim_bf_controller";
        if (!active) {
            return;
        }

        print("[AS] Starting bruteforce..");

        @m_simManager = simManager;

        // knock off finish event from the input buffer
        m_simManager.InputEvents.RemoveAt(m_simManager.InputEvents.Length - 1);
        
        // handle variables 
        UpdateSettings(); // variables for bruteforce handlers
        SetBruteforceVariables(); // variables for bruteforce

        // one time variables that cannot be changed during simulation
        FillMissingInputs(simManager);

        m_phase = BFPhase::Initial;
        m_originalSimulationStates = array<SimulationState@>();
        m_originalInputEvents.Clear();
    }

    void OnSimulationEnd(SimulationManager@ simManager) {
        if (!active) {
            return;
        }
        print("[AS] Bruteforce finished");
        active = false;

        m_originalSimulationStates = array<SimulationState@>();
    }

    void FillMissingInputs(SimulationManager@ simManager) {
        // fill in a steering/acceleration/brake value for next tick if it is empty, using the previous tick's value
        TM::InputEventBuffer@ inputBuffer = simManager.InputEvents;
        // to check a input type
        EventIndices actionIndices = inputBuffer.EventIndices;

        // steering
        if (m_useFillMissingInputsSteering) {
            auto originalSteeringValuesIndices = simManager.InputEvents.Find(-1, InputType::Steer);
            array<uint> originalSteeringValues = array<uint>();
            for (uint i = 0; i < originalSteeringValuesIndices.Length; i++) {
                originalSteeringValues.Add(inputBuffer[originalSteeringValuesIndices[i]].Value.Analog);
            }
            auto originalSteeringTimes = array<uint>();
            for (uint i = 0; i < originalSteeringValuesIndices.Length; i++) {
                originalSteeringTimes.Add((inputBuffer[originalSteeringValuesIndices[i]].Time - 100010) / 10);
            }

            int minTime = 0;
            int maxTime = (simManager.EventsDuration - 10) / 10;

            // if no steering occurred at the start, add steering value of 0 to start
            if (originalSteeringTimes.Length == 0 || originalSteeringTimes.Length > 0 && originalSteeringTimes[0] != 0) {
                originalSteeringTimes.InsertAt(0, 0);
                originalSteeringValues.InsertAt(0, 0);
                // also manually add the first steering value to the input buffer
                inputBuffer.Add(0, InputType::Steer, 0);
            }

            int currentOriginalSteeringTimesIndex = originalSteeringTimes.Length - 1;

            // iterate through all the times and fill in the empty steering values with the previous steering value
            for (int i = maxTime; i >= minTime; i--) {
                if (uint(i) > originalSteeringTimes[currentOriginalSteeringTimesIndex]) {
                    inputBuffer.Add(i * 10, InputType::Steer, originalSteeringValues[currentOriginalSteeringTimesIndex]);
                } else {
                    currentOriginalSteeringTimesIndex--;
                    if (currentOriginalSteeringTimesIndex < 0) {
                        break;
                    }
                }
            }
        }

        if (m_useFillMissingInputsAcceleration) {
            // acceleration
            auto originalAccelerationValuesIndices = simManager.InputEvents.Find(-1, InputType::Up);
            array<uint> originalAccelerationValues = array<uint>();
            for (uint i = 0; i < originalAccelerationValuesIndices.Length; i++) {
                originalAccelerationValues.Add(inputBuffer[originalAccelerationValuesIndices[i]].Value.Binary == false ? 0 : 1);
            }
            auto originalAccelerationTimes = array<uint>();
            for (uint i = 0; i < originalAccelerationValuesIndices.Length; i++) {
                originalAccelerationTimes.Add((inputBuffer[originalAccelerationValuesIndices[i]].Time - 100010) / 10);
            }

            int minTime = 0;
            int maxTime = (simManager.EventsDuration - 10) / 10;
            
            // if no acceleration occurred at the start, add acceleration value of 0 to start
            if (originalAccelerationTimes.Length == 0 || originalAccelerationTimes.Length > 0 && originalAccelerationTimes[0] != 0) {
                originalAccelerationTimes.InsertAt(0, 0);
                originalAccelerationValues.InsertAt(0, 0);
                // also manually add the first acceleration value to the input buffer
                inputBuffer.Add(0, InputType::Up, 0);
            }

            int currentOriginalAccelerationTimesIndex = originalAccelerationTimes.Length - 1;

            // iterate through all the times and fill in the empty acceleration values with the previous acceleration value
            for (int i = maxTime; i >= minTime; i--) {
                if (uint(i) > originalAccelerationTimes[currentOriginalAccelerationTimesIndex]) {
                    inputBuffer.Add(i * 10, InputType::Up, originalAccelerationValues[currentOriginalAccelerationTimesIndex]);
                } else {
                    currentOriginalAccelerationTimesIndex--;
                    if (currentOriginalAccelerationTimesIndex < 0) {
                        break;
                    }
                }
            }
        }

        if (m_useFillMissingInputsBrake) {
            // brake
            auto originalBrakeValuesIndices = simManager.InputEvents.Find(-1, InputType::Down);
            array<uint> originalBrakeValues = array<uint>();
            for (uint i = 0; i < originalBrakeValuesIndices.Length; i++) {
                originalBrakeValues.Add(inputBuffer[originalBrakeValuesIndices[i]].Value.Binary == false ? 0 : 1);
            }
            auto originalBrakeTimes = array<uint>();
            for (uint i = 0; i < originalBrakeValuesIndices.Length; i++) {
                originalBrakeTimes.Add((inputBuffer[originalBrakeValuesIndices[i]].Time - 100010) / 10);
            }

            int minTime = 0;
            int maxTime = (simManager.EventsDuration - 10) / 10;

            // if no brake occurred at the start, add brake value of 0 to start
            if (originalBrakeTimes.Length == 0 || originalBrakeTimes.Length > 0 && originalBrakeTimes[0] != 0) {
                originalBrakeTimes.InsertAt(0, 0);
                originalBrakeValues.InsertAt(0, 0);
                // also manually add the first brake value to the input buffer
                inputBuffer.Add(0, InputType::Down, 0);
            }

            int currentOriginalBrakeTimesIndex = originalBrakeTimes.Length - 1;

            // iterate through all the times and fill in the empty brake values with the previous brake value
            for (int i = maxTime; i >= minTime; i--) {
                if (uint(i) > originalBrakeTimes[currentOriginalBrakeTimesIndex]) {
                    inputBuffer.Add(i * 10, InputType::Down, originalBrakeValues[currentOriginalBrakeTimesIndex]);
                } else {
                    currentOriginalBrakeTimesIndex--;
                    if (currentOriginalBrakeTimesIndex < 0) {
                        break;
                    }
                }
            }
        }
    }

    void PrintInputBuffer() {
        // somehow this doesnt show steering events properly after i filled in the missing inputs, but it does work for acceleration and brake
        print(m_simManager.InputEvents.ToCommandsText(InputFormatFlags(3)));
    }

    void RandomNeighbour() {
        TM::InputEventBuffer@ inputBuffer = m_simManager.InputEvents;

        /*        
        // remove unnecessary events from inputBuffer (TODO: keep, remove? it doesnt ask for m_customStopTimeDelta either right now, but it does seem to work)
        if (int(inputBuffer[inputBuffer.Length - 1].Time - 100010) > m_bestTime) {
            uint removeIndex = inputBuffer.Length - 1;
            while (int(inputBuffer[removeIndex].Time - 100010) > m_bestTime) {
                removeIndex -= 1;
            }
            inputBuffer.RemoveAt(removeIndex + 1, inputBuffer.Length - removeIndex);
        }
        */


        m_rewindIndex = 2147483647;
        uint lowestTimeModified = 2147483647;

        // copy inputBuffer into m_originalInputEvents
        m_originalInputEvents.Clear();
        for (uint i = 0; i < inputBuffer.Length; i++) {
            m_originalInputEvents.Add(inputBuffer[i]);
        }


        uint steerValuesModified = 0;
        uint accelerationValuesModified = 0;
        uint brakeValuesModified = 0;

        uint modifySteeringMinTime = Math::Max(0, m_modifySteeringMinTime);
        uint modifySteeringMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifySteeringMaxTime = m_modifySteeringMaxTime == 0 ? modifySteeringMaxTime : Math::Min(modifySteeringMaxTime, m_modifySteeringMaxTime);

        uint modifyAccelerationMinTime = Math::Max(0, m_modifyAccelerationMinTime);
        uint modifyAccelerationMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifyAccelerationMaxTime = m_modifyAccelerationMaxTime == 0 ? modifyAccelerationMaxTime : Math::Min(modifyAccelerationMaxTime, m_modifyAccelerationMaxTime);

        uint modifyBrakeMinTime = Math::Max(0, m_modifyBrakeMinTime);
        uint modifyBrakeMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifyBrakeMaxTime = m_modifyBrakeMaxTime == 0 ? modifyBrakeMaxTime : Math::Min(modifyBrakeMaxTime, m_modifyBrakeMaxTime);

        // indices that were present in the replay
        auto originalSteeringValuesIndices = inputBuffer.Find(-1, InputType::Steer, Math::INT_MAX);
        auto originalAccelerationValuesIndices = inputBuffer.Find(-1, InputType::Up, Math::INT_MAX);
        auto originalBrakeValuesIndices = inputBuffer.Find(-1, InputType::Down, Math::INT_MAX);

        uint maxSteeringModifyCount = Math::Rand(m_modifySteeringMinCount, m_modifySteeringMaxCount);
        uint maxAccelerationModifyCount = Math::Rand(m_modifyAccelerationMinCount, m_modifyAccelerationMaxCount);
        uint maxBrakeModifyCount = Math::Rand(m_modifyBrakeMinCount, m_modifyBrakeMaxCount);

        // we either modify an existing value or add a new one
        // we do this until we have reached the max amount of modifications

        // steering
        while (steerValuesModified < maxSteeringModifyCount) {
            // generate a random time value
            uint modifyTime = uint(Math::Rand(modifySteeringMinTime, modifySteeringMaxTime) / 10) * 10;

            // check if there is already a value at that time
            auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Steer);
            // if there is no value at that time, add a new one
            if (modifyIndex.Length == 0) {
                // add a new value
                int newValue = Math::Rand(-m_modifySteeringMaxDiff/2, m_modifySteeringMaxDiff/2);
                inputBuffer.Add(modifyTime, InputType::Steer, newValue);
                
                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                steerValuesModified++;

                if (m_modifySteeringMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifySteeringMinHoldTime / 10, m_modifySteeringMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifySteeringMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Steer);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Steer, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Analog = newValue;
                        }
                        startTime += 10;
                    }
                } else {
                    // check if next neighbouring tick is not a steer event, and if so, add a new one with value 0
                    if (modifyTime + 10 < modifySteeringMaxTime) {
                        auto nextIndex = inputBuffer.Find(modifyTime + 10, InputType::Steer);
                        if (nextIndex.Length == 0) {
                            inputBuffer.Add(modifyTime + 10, InputType::Steer, 0);
                        }
                    }
                }
            } else {
                // if there is a value at that time, modify it
                int oldSteerValue = inputBuffer[modifyIndex[0]].Value.Analog;
                int newValue = oldSteerValue + Math::Rand(-Math::Min(65536 + oldSteerValue, m_modifySteeringMaxDiff), Math::Min(65536 - oldSteerValue, m_modifySteeringMaxDiff));
                inputBuffer[modifyIndex[0]].Value.Analog = newValue;

                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                steerValuesModified++;
                
                if (m_modifySteeringMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifySteeringMinHoldTime / 10, m_modifySteeringMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifySteeringMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Steer);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Steer, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Analog = newValue;
                        }
                        startTime += 10;
                    }
                }
            }
        }

        // acceleration
        while (accelerationValuesModified < maxAccelerationModifyCount) {
            // generate a random time value
            uint modifyTime = uint(Math::Rand(modifyAccelerationMinTime, modifyAccelerationMaxTime) / 10) * 10;

            // check if there is already a value at that time
            auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Up);
            // if there is no value at that time, add a new one
            if (modifyIndex.Length == 0) {
                // add a new value
                int newValue = Math::Rand(0, 1);
                inputBuffer.Add(modifyTime, InputType::Up, newValue);
                
                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                accelerationValuesModified++;

                if (m_modifyAccelerationMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifyAccelerationMinHoldTime / 10, m_modifyAccelerationMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifyAccelerationMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Up);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Up, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Binary = newValue == 1 ? true : false;
                        }
                        startTime += 10;
                    }
                } else {
                    // check if next neighbouring tick is not a acceleration event, and if so, add a new one with value 0
                    if (modifyTime + 10 < modifyAccelerationMaxTime) {
                        auto nextIndex = inputBuffer.Find(modifyTime + 10, InputType::Up);
                        if (nextIndex.Length == 0) {
                            inputBuffer.Add(modifyTime + 10, InputType::Up, 0);
                        }
                    }
                }
            } else {
                // if there is a value at that time, modify it
                int newValue = Math::Rand(0, 1);
                inputBuffer[modifyIndex[0]].Value.Binary = newValue == 1 ? true : false;
                
                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                accelerationValuesModified++;
                
                if (m_modifyAccelerationMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifyAccelerationMinHoldTime / 10, m_modifyAccelerationMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifyAccelerationMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Up);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Up, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Binary = newValue == 1 ? true : false;
                        }
                        startTime += 10;
                    }
                }
            }
        }
        
        // brake
        while (brakeValuesModified < maxBrakeModifyCount) {
            // generate a random time value
            uint modifyTime = uint(Math::Rand(modifyBrakeMinTime, modifyBrakeMaxTime) / 10) * 10;

            // check if there is already a value at that time
            auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Down);
            // if there is no value at that time, add a new one
            if (modifyIndex.Length == 0) {
                // add a new value
                int newValue = Math::Rand(0, 1);
                inputBuffer.Add(modifyTime, InputType::Down, newValue);
                
                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                brakeValuesModified++;

                if (m_modifyBrakeMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifyBrakeMinHoldTime / 10, m_modifyBrakeMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifyBrakeMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Down);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Down, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Binary = newValue == 1 ? true : false;
                        }
                        startTime += 10;
                    }
                } else {
                    // check if next neighbouring tick is not a Brake event, and if so, add a new one with value 0
                    if (modifyTime + 10 < modifyBrakeMaxTime) {
                        auto nextIndex = inputBuffer.Find(modifyTime + 10, InputType::Down);
                        if (nextIndex.Length == 0) {
                            inputBuffer.Add(modifyTime + 10, InputType::Down, 0);
                        }
                    }
                }
            } else {
                // if there is a value at that time, modify it
                int newValue = Math::Rand(0, 1);
                inputBuffer[modifyIndex[0]].Value.Binary = newValue == 1 ? true : false;

                lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);
                brakeValuesModified++;
                
                if (m_modifyBrakeMaxHoldTime > 0) {
                    uint holdTime = Math::Rand(m_modifyBrakeMinHoldTime / 10, m_modifyBrakeMaxHoldTime / 10) * 10;
                    uint startTime = modifyTime + 10;
                    uint endTime = Math::Min(startTime + holdTime, modifyBrakeMaxTime);
                    while (startTime < endTime) {
                        auto idx = inputBuffer.Find(startTime, InputType::Down);
                        if (idx.Length == 0) {
                            inputBuffer.Add(startTime, InputType::Down, newValue);
                        } else {
                            inputBuffer[idx[0]].Value.Binary = newValue == 1 ? true : false;
                        }
                        startTime += 10;
                    }
                }
            }
        }

        if (lowestTimeModified == 0 || lowestTimeModified == 2147483647) {
            m_rewindIndex = 0;
        } else {
            m_rewindIndex = lowestTimeModified / 10 - 1;
        }

        if (m_originalSimulationStates[m_originalSimulationStates.Length-1].PlayerInfo.RaceTime < int(m_rewindIndex * 10)) {
            print("[AS] Rewind time is higher than highest saved simulation state, this can happen when custom stop time is > 0 and inputs were generated that occurred beyond the finish time that was driven during the initial phase. RandomNeighbour will be called again. If this keeps happening, lower the custom stop time.", Severity::Warning);
            RandomNeighbour();
        }

    }

    void OnSimulationStep(SimulationManager@ simManager) {
        if (!active) {
            return;
        }

        BFEvaluationInfo info;
        info.Phase = m_phase;
        
        BFEvaluationResponse evalResponse = OnBruteforceStep(simManager, info);

        switch(evalResponse.Decision) {
            case BFEvaluationDecision::DoNothing:
                if (m_phase == BFPhase::Initial) {
                    CollectInitialPhaseData(simManager);
                }
                break;
            case BFEvaluationDecision::Accept:
                if (m_phase == BFPhase::Initial) {
                    StartSearchPhase();
                    break;
                }

                // save to file
                m_commandList.Content = simManager.InputEvents.ToCommandsText(InputFormatFlags(3));
                // m_commandList.Content = simManager.InputEvents.ToCommandsText();
                m_commandList.Save(m_resultFileName);

                m_originalInputEvents.Clear();
                StartInitialPhase();
                break;
            case BFEvaluationDecision::Reject:
                if (m_phase == BFPhase::Initial) {
                    print("[AS] Cannot reject in initial phase, ignoring");
                    break;
                }

                RestoreInputBuffer();
                StartNewIteration();
                break;
            case BFEvaluationDecision::Stop:
                print("[AS] Stopped");
                OnSimulationEnd(simManager);
                break;
        }
    }

    void RestoreInputBuffer()
    {
        m_simManager.InputEvents.Clear();
        for (uint i = 0; i < m_originalInputEvents.Length; i++) {
            m_simManager.InputEvents.Add(m_originalInputEvents[i]);
        }
        m_originalInputEvents.Clear();
    }

    void OnCheckpointCountChanged(SimulationManager@ simManager, int count, int target) {
        if (!active) {
            return;
        }

        if (m_simManager.PlayerInfo.RaceFinished) {
            m_simManager.PreventSimulationFinish();
        }
    }

    void CollectInitialPhaseData(SimulationManager@ simManager) {
        if (simManager.RaceTime >= 0) {
            m_originalSimulationStates.Add(m_simManager.SaveState());
        }
    }

    void HandleSearchPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, BFEvaluationInfo&in info) {
        if (m_usePreciseTime) {
            PreciseFin::HandleSearchPhase(m_simManager, response, info);
            return;
        } else {
            NormalFin::HandleSearchPhase(m_simManager, response, info);
            return;
        }
    }

    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, BFEvaluationInfo&in info) {
        if (m_usePreciseTime) {
            PreciseFin::HandleInitialPhase(m_simManager, response, info);
            return;
        } else {
            NormalFin::HandleInitialPhase(m_simManager, response, info);
            return;
        }
    }

    BFEvaluationResponse@ OnBruteforceStep(SimulationManager@ simManager, const BFEvaluationInfo&in info) {
        BFEvaluationResponse response;

        switch(info.Phase) {
            case BFPhase::Initial:
                HandleInitialPhase(simManager, response, info);
                break;
            case BFPhase::Search:
                HandleSearchPhase(simManager, response, info);
                break;
        }

        return response;
    }

    // informational functions
    void PrintBruteforceInfo() {
        if (!m_useInfoLogging && !m_useIterLogging) {
            return;
        }
        
        string message = "[AS] ";

        if (m_useInfoLogging) {
            if (m_usePreciseTime) {
                message += "best precise time: " + DecimalFormatted(PreciseFin::bestPreciseTime, 16);
            } else {
                message += "best time: " + Text::FormatInt(m_bestTime);
            }
        }

        if (m_useIterLogging) {
            if (m_useInfoLogging) {
                message += " | ";
            }
            message += "iterations: " + Text::FormatInt(m_iterations) + " | iters/sec: " + DecimalFormatted(m_iterationsPerSecond, 2);
        }

        print(message);
    }

    void UpdateIterationsPerSecond() {
        m_iterations++;
        m_iterationsCounter++;

        if (m_iterationsCounter % 200 == 0) {
            PrintBruteforceInfo();

            float currentTime = float(Time::Now);
            currentTime /= 1000.0f;
            float timeSinceLastUpdate = currentTime - m_lastIterationsPerSecondUpdate;
            m_iterationsPerSecond = float(m_iterationsCounter) / timeSinceLastUpdate;
            m_lastIterationsPerSecondUpdate = currentTime;
            m_iterationsCounter = 0;
        }
    }

    SimulationManager@ m_simManager;
    CommandList m_commandList;
    bool active = false;
    BFPhase m_phase;

    array<SimulationState@> m_originalSimulationStates = {};
    array<TM::InputEvent> m_originalInputEvents; 

    private uint m_rewindIndex = 0;
}

class Manager {
    Manager() {
        @m_controller = BruteforceController();
    }
    ~Manager() {}

    void OnSimulationBegin(SimulationManager@ simManager) {
        @m_simManager = simManager;
        m_simManager.RemoveStateValidation();
        m_controller.OnSimulationBegin(simManager);
    }

    void OnSimulationStep(SimulationManager@ simManager, bool userCancelled) {
        if (userCancelled) {
            m_controller.OnSimulationEnd(simManager);
            return;
        }

        m_controller.OnSimulationStep(simManager);
    }

    void OnSimulationEnd(SimulationManager@ simManager, uint result) {
        m_controller.OnSimulationEnd(simManager);
    }

    void OnCheckpointCountChanged(SimulationManager@ simManager, int count, int target) {
        m_controller.OnCheckpointCountChanged(simManager, count, target);
    }

    SimulationManager@ m_simManager;
    BruteforceController@ m_controller;
}

/* these functions are called from the game, we relay them to our manager */
void OnSimulationBegin(SimulationManager@ simManager) {
    m_Manager.OnSimulationBegin(simManager);
}

void OnSimulationEnd(SimulationManager@ simManager, uint result) {
    m_Manager.OnSimulationEnd(simManager, result);
}

void OnSimulationStep(SimulationManager@ simManager, bool userCancelled) {
    m_Manager.OnSimulationStep(simManager, userCancelled);
}

void OnCheckpointCountChanged(SimulationManager@ simManager, int count, int target) {
    m_Manager.OnCheckpointCountChanged(simManager, count, target);
}

void BruteforceSettingsWindow() {
    UI::Dummy(vec2(0, 15));

    UI::TextDimmed("Options:");

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // m_resultFileName
    UI::PushItemWidth(120);
    if (!m_Manager.m_controller.active) {
        m_resultFileName = UI::InputTextVar("Result file name", "kim_bf_result_file_name");
    } else {
        UI::Text("Result file name " + m_resultFileName);
    }
    UI::PopItemWidth();

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // m_target selectable
    UI::PushItemWidth(120);
    UI::Text("Target");
    UI::SameLine();
    
    if (!m_Manager.m_controller.active) {
        m_target = GetVariableString("kim_bf_target");
        if (UI::BeginCombo("##target", m_target)) {
            for (uint i = 0; i < targetNames.Length; i++) {
                bool isSelected = m_target == targetNames[i];
                if (UI::Selectable(targetNames[i], isSelected)) {
                    m_target = targetNames[i];
                    SetVariable("kim_bf_target", targetNames[i]);
                }
            }
            UI::EndCombo();
        }
    } else {
        UI::Text(m_target);
    }

    UI::TextDimmed("(only finish is implemented atm)");
    UI::PopItemWidth();

    
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));
    
    // precise time checkbox
    UI::PushItemWidth(180);
    m_usePreciseTime = UI::CheckboxVar("##precisetimeenabled", "kim_bf_use_precise_time");
    UI::SameLine();
    UI::Text("Use precise time");

    if (m_usePreciseTime) {
        // precise time precision
        UI::SameLine();
        // TODO: inputintvar is not enough to accept 64 bit values
        int preciseTimePrecision = UI::InputIntVar("##precisetimeprecision", "kim_bf_precise_time_precision", 1);
        if (preciseTimePrecision < 1) {
            preciseTimePrecision = 1;
            SetVariable("kim_bf_precise_time_precision", 1);
        }
        m_preciseTimePrecision = preciseTimePrecision;
        UI::SameLine();
        UI::Text("Precision");
        UI::TextDimmed("1 = max precision. higher values = less precision. theoretical maximum is 2^64-1, however this field is limited to 32 bit values. Also 1 might be completely overkill and higher values could lead to the same result.");
    }
    
    UI::PopItemWidth();

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // kim_bf_modify_steering_min_time, kim_bf_modify_steering_max_time,
    // kim_bf_modify_acceleration_min_time, kim_bf_modify_acceleration_max_time,
    // kim_bf_modify_brake_min_time, kim_bf_modify_brake_max_time
    UI::PushItemWidth(180);
    UI::Text("Input Modifications Time Range:");
    UI::Dummy(vec2(0, 5));
    UI::Text("Steering:");
    UI::Text("Min Time");
    UI::SameLine();
    int modifySteeringMinTime = UI::InputTimeVar("##modifysteeringmintime", "kim_bf_modify_steering_min_time", 10);
    if (uint(modifySteeringMinTime) > m_modifySteeringMaxTime) {
        m_modifySteeringMaxTime = modifySteeringMinTime;
        SetVariable("kim_bf_modify_steering_max_time", modifySteeringMinTime);
    }
    m_modifySteeringMinTime = modifySteeringMinTime;
    UI::SameLine();
    UI::Text("  Max Time");
    UI::SameLine();
    int modifySteeringMaxTime = UI::InputTimeVar("##modifysteeringmaxtime", "kim_bf_modify_steering_max_time", 10);
    if (uint(modifySteeringMaxTime) < m_modifySteeringMinTime) {
        m_modifySteeringMinTime = modifySteeringMaxTime;
        SetVariable("kim_bf_modify_steering_min_time", modifySteeringMaxTime);
    }
    m_modifySteeringMaxTime = modifySteeringMaxTime;
    UI::Dummy(vec2(0, 5));
    UI::Text("Acceleration:");
    UI::Text("Min Time");
    UI::SameLine();
    int modifyAccelerationMinTime = UI::InputTimeVar("##modifyaccelerationmintime", "kim_bf_modify_acceleration_min_time", 10);
    if (uint(modifyAccelerationMinTime) > m_modifyAccelerationMaxTime) {
        m_modifyAccelerationMaxTime = modifyAccelerationMinTime;
        SetVariable("kim_bf_modify_acceleration_max_time", modifyAccelerationMinTime);
    }
    m_modifyAccelerationMinTime = modifyAccelerationMinTime;
    UI::SameLine();
    UI::Text("  Max Time");
    UI::SameLine();
    int modifyAccelerationMaxTime = UI::InputTimeVar("##modifyaccelerationmaxtime", "kim_bf_modify_acceleration_max_time", 10);
    if (uint(modifyAccelerationMaxTime) < m_modifyAccelerationMinTime) {
        m_modifyAccelerationMinTime = modifyAccelerationMaxTime;
        SetVariable("kim_bf_modify_acceleration_min_time", modifyAccelerationMaxTime);
    }
    m_modifyAccelerationMaxTime = modifyAccelerationMaxTime;
    UI::Dummy(vec2(0, 5));
    UI::Text("Brake:");
    UI::Text("Min Time");
    UI::SameLine();
    int modifyBrakeMinTime = UI::InputTimeVar("##modifybrakemintime", "kim_bf_modify_brake_min_time", 10);
    if (uint(modifyBrakeMinTime) > m_modifyBrakeMaxTime) {
        m_modifyBrakeMaxTime = modifyBrakeMinTime;
        SetVariable("kim_bf_modify_brake_max_time", modifyBrakeMinTime);
    }
    m_modifyBrakeMinTime = modifyBrakeMinTime;
    UI::SameLine();
    UI::Text("  Max Time");
    UI::SameLine();
    int modifyBrakeMaxTime = UI::InputTimeVar("##modifybrakemaxtime", "kim_bf_modify_brake_max_time", 10);
    if (uint(modifyBrakeMaxTime) < m_modifyBrakeMinTime) {
        m_modifyBrakeMinTime = modifyBrakeMaxTime;
        SetVariable("kim_bf_modify_brake_min_time", modifyBrakeMaxTime);
    }
    m_modifyBrakeMaxTime = modifyBrakeMaxTime;
    UI::PopItemWidth();
    UI::TextDimmed("A random time value between min/max time is picked and from that point on inputs are modified. Inputs will _never_ be modified beyond the max time.");

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // kim_bf_modify_steering_min_count, kim_bf_modify_steering_max_count,
    // kim_bf_modify_acceleration_min_count, kim_bf_modify_acceleration_max_count,
    // kim_bf_modify_brake_min_count, kim_bf_modify_brake_max_count
    UI::PushItemWidth(120);
    UI::Text("Input Modifications amount:");
    int modifySteeringMinCount = Math::Max(UI::InputIntVar("Steer Min Amount        ", "kim_bf_modify_steering_min_count", 1), 0);
    SetVariable("kim_bf_modify_steering_min_count", modifySteeringMinCount);
    if (uint(modifySteeringMinCount) > m_modifySteeringMaxCount) {
        SetVariable("kim_bf_modify_steering_max_count", modifySteeringMinCount);
    }
    UI::SameLine();
    int modifySteeringMaxCount = Math::Max(UI::InputIntVar("Steer Max Amount", "kim_bf_modify_steering_max_count", 1), 0);
    SetVariable("kim_bf_modify_steering_max_count", modifySteeringMaxCount);
    if (uint(modifySteeringMaxCount) < m_modifySteeringMinCount) {
        SetVariable("kim_bf_modify_steering_min_count", modifySteeringMaxCount);
    }
    m_modifySteeringMinCount = modifySteeringMinCount;
    m_modifySteeringMaxCount = modifySteeringMaxCount;

    int modifyAccelerationMinCount = Math::Max(UI::InputIntVar("Accel Min Amount        ", "kim_bf_modify_acceleration_min_count", 1), 0);
    SetVariable("kim_bf_modify_acceleration_min_count", modifyAccelerationMinCount);
    if (uint(modifyAccelerationMinCount) > m_modifyAccelerationMaxCount) {
        SetVariable("kim_bf_modify_acceleration_max_count", modifyAccelerationMinCount);
    }
    UI::SameLine();
    int modifyAccelerationMaxCount = Math::Max(UI::InputIntVar("Accel Max Amount", "kim_bf_modify_acceleration_max_count", 1), 0);
    SetVariable("kim_bf_modify_acceleration_max_count", modifyAccelerationMaxCount);
    if (uint(modifyAccelerationMaxCount) < m_modifyAccelerationMinCount) {
        SetVariable("kim_bf_modify_acceleration_min_count", modifyAccelerationMaxCount);
    }
    m_modifyAccelerationMinCount = modifyAccelerationMinCount;
    m_modifyAccelerationMaxCount = modifyAccelerationMaxCount;

    int modifyBrakeMinCount = Math::Max(UI::InputIntVar("Brake Min Amount       ", "kim_bf_modify_brake_min_count", 1), 0);
    SetVariable("kim_bf_modify_brake_min_count", modifyBrakeMinCount);
    if (uint(modifyBrakeMinCount) > m_modifyBrakeMaxCount) {
        SetVariable("kim_bf_modify_brake_max_count", modifyBrakeMinCount);
    }
    UI::SameLine();
    int modifyBrakeMaxCount = Math::Max(UI::InputIntVar("Brake Max Amount", "kim_bf_modify_brake_max_count", 1), 0);
    SetVariable("kim_bf_modify_brake_max_count", modifyBrakeMaxCount);
    if (uint(modifyBrakeMaxCount) < m_modifyBrakeMinCount) {
        SetVariable("kim_bf_modify_brake_min_count", modifyBrakeMaxCount);
    }
    m_modifyBrakeMinCount = modifyBrakeMinCount;
    m_modifyBrakeMaxCount = modifyBrakeMaxCount;

    if (m_modifySteeringMaxCount == 0 && m_modifyAccelerationMaxCount == 0 && m_modifyBrakeMaxCount == 0) {
        UI::TextDimmed("Warning: No input modifications will be made!");
    }
    UI::TextDimmed("A random value between min/max amount is picked and that's how many inputs will be modified. Note inputs will not be modified beyond the input max time.");
    
    UI::PopItemWidth();

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // m_modifySteeringMinHoldTime, m_modifySteeringMaxHoldTime,
    // m_modifyAccelerationMinHoldTime, m_modifyAccelerationMaxHoldTime,
    // m_modifyBrakeMinHoldTime, m_modifyBrakeMaxHoldTime
    // TODO: in ui the +- buttons for the Max variants dont react when clicking once, but when holding, needs fixing
    UI::PushItemWidth(180);
    UI::Text("Input Modification Hold Time:");
    int modifySteeringMinHoldTime = Math::Max(UI::InputTimeVar("Steer Min Hold", "kim_bf_modify_steering_min_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_steering_min_hold_time", modifySteeringMinHoldTime);
    if (uint(modifySteeringMinHoldTime) > m_modifySteeringMaxHoldTime) {
        SetVariable("kim_bf_modify_steering_max_hold_time", modifySteeringMinHoldTime);
    }
    UI::SameLine();
    int modifySteeringMaxHoldTime = Math::Max(UI::InputTimeVar("Steer Max Hold", "kim_bf_modify_steering_max_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_steering_max_hold_time", modifySteeringMaxHoldTime);
    if (uint(modifySteeringMaxHoldTime) < m_modifySteeringMinHoldTime) {
        SetVariable("kim_bf_modify_steering_min_hold_time", modifySteeringMaxHoldTime);
    }
    m_modifySteeringMinHoldTime = modifySteeringMinHoldTime;
    m_modifySteeringMaxHoldTime = modifySteeringMaxHoldTime;

    int modifyAccelerationMinHoldTime = Math::Max(UI::InputTimeVar("Accel Min Hold", "kim_bf_modify_acceleration_min_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_acceleration_min_hold_time", modifyAccelerationMinHoldTime);
    if (uint(modifyAccelerationMinHoldTime) > m_modifyAccelerationMaxHoldTime) {
        SetVariable("kim_bf_modify_acceleration_max_hold_time", modifyAccelerationMinHoldTime);
    }
    UI::SameLine();
    int modifyAccelerationMaxHoldTime = Math::Max(UI::InputTimeVar("Accel Max Hold", "kim_bf_modify_acceleration_max_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_acceleration_max_hold_time", modifyAccelerationMaxHoldTime);
    if (uint(modifyAccelerationMaxHoldTime) < m_modifyAccelerationMinHoldTime) {
        SetVariable("kim_bf_modify_acceleration_min_hold_time", modifyAccelerationMaxHoldTime);
    }
    m_modifyAccelerationMinHoldTime = modifyAccelerationMinHoldTime;
    m_modifyAccelerationMaxHoldTime = modifyAccelerationMaxHoldTime;

    int modifyBrakeMinHoldTime = Math::Max(UI::InputTimeVar("Brake Min Hold", "kim_bf_modify_brake_min_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_brake_min_hold_time", modifyBrakeMinHoldTime);
    if (uint(modifyBrakeMinHoldTime) > m_modifyBrakeMaxHoldTime) {
        SetVariable("kim_bf_modify_brake_max_hold_time", modifyBrakeMinHoldTime);
    }
    UI::SameLine();
    int modifyBrakeMaxHoldTime = Math::Max(UI::InputTimeVar("Brake Max Hold", "kim_bf_modify_brake_max_hold_time", 10, 0), 0);
    SetVariable("kim_bf_modify_brake_max_hold_time", modifyBrakeMaxHoldTime);
    if (uint(modifyBrakeMaxHoldTime) < m_modifyBrakeMinHoldTime) {
        SetVariable("kim_bf_modify_brake_min_hold_time", modifyBrakeMaxHoldTime);
    }
    m_modifyBrakeMinHoldTime = modifyBrakeMinHoldTime;
    m_modifyBrakeMaxHoldTime = modifyBrakeMaxHoldTime;
    UI::TextDimmed("Specifies how long the input will be held for. Note inputs will not be modified beyond the input max time. It also counts as 1 input modification even if multiple ticks are filled");

    UI::PopItemWidth();
    
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    UI::PushItemWidth(120);
    UI::Text("Steering Modfication Value Range:");
    int modifySteeringMinDiff = Math::Clamp(UI::SliderIntVar("Min Steer Diff          ", "kim_bf_modify_steering_min_diff", 1, 131072), 1, 131072);
    SetVariable("kim_bf_modify_steering_min_diff", modifySteeringMinDiff);
    if (uint(modifySteeringMinDiff) > m_modifySteeringMaxDiff) {
        SetVariable("kim_bf_modify_steering_max_diff", modifySteeringMinDiff);
    }
    UI::SameLine();
    int modifySteeringMaxDiff = Math::Clamp(UI::SliderIntVar("Max Steer Diff", "kim_bf_modify_steering_max_diff", 1, 131072), 1, 131072);
    SetVariable("kim_bf_modify_steering_max_diff", modifySteeringMaxDiff);
    if (uint(modifySteeringMaxDiff) < m_modifySteeringMinDiff) {
        SetVariable("kim_bf_modify_steering_min_diff", modifySteeringMaxDiff);
    }

    m_modifySteeringMinDiff = modifySteeringMinDiff;
    m_modifySteeringMaxDiff = modifySteeringMaxDiff;
    UI::TextDimmed("You already know what this is");

    UI::PopItemWidth();
    
    /* TODO: implement
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // kim_bf_modify_only_existing_inputs
    m_modifyOnlyExistingInputs = UI::CheckboxVar("Modify Only Existing Inputs", "kim_bf_modify_only_existing_inputs");
    */

    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    UI::Text("Fill Missing Inputs:");
    // kim_bf_use_fill_missing_inputs_steering, kim_bf_use_fill_missing_inputs_acceleration, kim_bf_use_fill_missing_inputs_brake
    if (!m_Manager.m_controller.active) {
        m_useFillMissingInputsSteering =  UI::CheckboxVar("Fill Missing Steering Input", "kim_bf_use_fill_missing_inputs_steering");
        m_useFillMissingInputsAcceleration = UI::CheckboxVar("Fill Missing Acceleration Input", "kim_bf_use_fill_missing_inputs_acceleration");
        m_useFillMissingInputsBrake = UI::CheckboxVar("Fill Missing Brake Input", "kim_bf_use_fill_missing_inputs_brake");
    } else {
        UI::Text("Fill Missing Steering Input: " + m_useFillMissingInputsSteering);
        UI::Text("Fill Missing Acceleration Input: " + m_useFillMissingInputsAcceleration);
        UI::Text("Fill Missing Brake Input: " + m_useFillMissingInputsBrake);
    }
    UI::TextDimmed("Example for steering: Timestamps with inputs will be filled with");
    UI::TextDimmed("existing values resulting in more values that can be changed.");
    UI::TextDimmed("1.00 steer 3456 -> 1.00 steer 3456");
    UI::TextDimmed("1.30 steer 1921     1.01 steer 3456");
    UI::TextDimmed("                                1.02 steer 3456");
    UI::TextDimmed("                                ...");
    UI::TextDimmed("                                1.30 steer 1921");


    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // custom stop time
    UI::PushItemWidth(180);
    // i use InputFloatVar because InputTimeVar doesn't allow for negative values
    auto previousCustomStopTimeDelta = m_customStopTimeDelta;
    m_customStopTimeDelta = UI::InputFloatVar("##overridestoptime", "kim_bf_custom_stop_time_delta", 0.01);
    
    UI::SameLine();
    // sec to hundreds, round, and then * 10 to milliseconds to conform game time
    if (!m_usePreciseTime) {
        m_customStopTimeDelta = double(Math::Round(m_customStopTimeDelta * 100.0) * 10.0);
        UI::Text("Custom stop time delta  ( " + DecimalFormatted(m_customStopTimeDelta, 0) + " ms)");
    } else {
        UI::Text("Custom stop time delta ( " + DecimalFormatted(m_customStopTimeDelta, 7) + " sec)");
        m_customStopTimeDelta = double(m_customStopTimeDelta * 1000.0);
    }

    if (previousCustomStopTimeDelta != m_customStopTimeDelta) {
        if (@m_Manager.m_simManager != null && m_Manager.m_controller.active) {
            m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
        }
    }
    
    UI::TextDimmed("Allow the car to drive until +/- the current best time during bruteforce. Example: Set it to -0.05 and it will only find improvements that are 0.05 sec better than the current best time. Set it to +0.05 if you force finished and you need to reach the finish line again.\nExtra note: This input field only allows 3 decimals, but you can still write down more precision, the value next to it shows the actual value that will be used.");
    UI::PopItemWidth();
    
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // kim_bf_use_info_logging
    m_useInfoLogging = UI::CheckboxVar("Log Info", "kim_bf_use_info_logging");
    UI::TextDimmed("Log information about the current run to the console.");

    // kim_bf_use_iter_logging
    m_useIterLogging = UI::CheckboxVar("Log Iterations", "kim_bf_use_iter_logging");
    UI::TextDimmed("Log information about each iteration to the console.");

    UI::TextDimmed("This stupidly prints to console every 200 iterations at the moment");

}

void Main() {
    @m_Manager = Manager();

    RegisterVariable("kim_bf_result_file_name", "result.txt");

    RegisterVariable("kim_bf_target", "finish"); // finish, cp, trigger (only finish implemented atm)

    RegisterVariable("kim_bf_use_precise_time", true);
    RegisterVariable("kim_bf_precise_time_precision", 1.0);

    RegisterVariable("kim_bf_modify_steering_min_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_time", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_max_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_time", 0.0);

    RegisterVariable("kim_bf_modify_steering_min_count", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_count", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_count", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_count", 1.0);
    RegisterVariable("kim_bf_modify_acceleration_max_count", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_count", 0.0);

    RegisterVariable("kim_bf_modify_steering_min_hold_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_hold_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_hold_time", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_hold_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_max_hold_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_hold_time", 0.0);

    RegisterVariable("kim_bf_modify_steering_min_diff", 1.0);
    RegisterVariable("kim_bf_modify_steering_max_diff", 131072.0);

    // TODO: implement
    // RegisterVariable("kim_bf_modify_only_existing_inputs", false);

    RegisterVariable("kim_bf_use_fill_missing_inputs_steering", false);
    RegisterVariable("kim_bf_use_fill_missing_inputs_acceleration", false);
    RegisterVariable("kim_bf_use_fill_missing_inputs_brake", false);

    RegisterVariable("kim_bf_custom_stop_time_delta", 0.0);

    RegisterVariable("kim_bf_use_info_logging", true);
    RegisterVariable("kim_bf_use_iter_logging", true);

    UpdateSettings();

    RegisterValidationHandler("kim_bf_controller", "[AS] Kim's Bruteforce Controller", BruteforceSettingsWindow);
}

PluginInfo@ GetPluginInfo() {
    auto info = PluginInfo();
    info.Name = "Kim's Bruteforce Controller";
    info.Author = "Kim";
    info.Version = "v1.0.0";
    info.Description = "General bruteforcing capabilities";
    return info;
}