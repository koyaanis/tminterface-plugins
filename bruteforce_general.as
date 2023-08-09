// constants
const array<string> targetNames = { "finish", "checkpoint", "trigger" };
const array<string> modifyTypes = { "amount", "percentage" };

Manager @m_Manager;

// _the_ var
bool m_useLiveDebugging = false;

// bruteforce vars
int m_bestTime; // best time the bf found so far, precise or not

// helper vars
bool m_wasBaseRunFound = false;
int m_bestTimeEver; // keeps track for the best time ever reached, useful for bf that allows for worse times to be found
bool m_canAcceptWorseTimes = false; // will become true if settings are set that allow for worse times to be found
bool m_customStopTimeDeltaIsIgnored = false; // used for m_customStopTimeDeltaUseOnlyOnce, will become true after the first time the custom stop time delta was used


// settings vars
string m_resultFileName;

bool m_usePreciseTime;
uint64 m_preciseTimePrecision;

uint m_modifySteeringMinTime;
uint m_modifyAccelerationMinTime;
uint m_modifyBrakeMinTime;
uint m_modifySteeringMaxTime;
uint m_modifyAccelerationMaxTime;
uint m_modifyBrakeMaxTime;

string m_modifyType; // "amount" / "percentage"
uint m_modifySteeringMinAmount;
uint m_modifyAccelerationMinAmount;
uint m_modifyBrakeMinAmount;
uint m_modifySteeringMaxAmount;
uint m_modifyAccelerationMaxAmount;
uint m_modifyBrakeMaxAmount;
double m_modifySteeringMinPercentage;
double m_modifyAccelerationMinPercentage;
double m_modifyBrakeMinPercentage;
double m_modifySteeringMaxPercentage;
double m_modifyAccelerationMaxPercentage;
double m_modifyBrakeMaxPercentage;

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

// specifies whether the stop time delta should only apply once for bruteforce and from that point on the stop time delta is ignored or if it should always use the stop time delta
bool m_customStopTimeDeltaUseOnlyOnce;
// todo: make the typing of this var less not good
double m_customStopTimeDelta;

// this will only be used for cases where worse times can be driven, meaning m_canAcceptWorseTimes has to be true, otherwise it has no effect
float m_worseResultAcceptanceProbability;

bool m_useInfoLogging;
bool m_useIterLogging;
uint m_loggingInterval;

// info vars
uint m_iterations = 0; // total iterations
uint m_iterationsCounter = 0; // iterations counter, used to update the iterations per second
float m_iterationsPerSecond = 0.0f; // iterations per second
float m_lastIterationsPerSecondUpdate = 0.0f; // last time the iterations per second were updated

/* enum definitions, because somehow we cant define enums inside a class */
enum TargetType {
    Finish,
    Checkpoint,
    Trigger
};


// helper functions
string DecimalFormatted(float number, int precision = 10) {
    return Text::FormatFloat(number, "{0:10f}", 0, precision);
}
string DecimalFormatted(double number, int precision = 10) {
    return Text::FormatFloat(number, "{0:10f}", 0, precision);
}

namespace NormalTime {
    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        int tickTime = simManager.TickTime;

        bool targetReached = false;
        switch (m_Manager.m_bfController.m_targetType) {
            case TargetType::Finish:
                targetReached = simManager.PlayerInfo.RaceFinished;
                break;
            case TargetType::Checkpoint:
                targetReached = simManager.PlayerInfo.CurCheckpointCount == m_Manager.m_bfController.m_targetId;
                break;
            case TargetType::Trigger:
                targetReached = GetTriggerByIndex(m_Manager.m_bfController.m_targetId - 1).ContainsPoint(simManager.Dyna.CurrentState.Location.Position);
                break;
        }
        
        // car is allowed to drive until this time (exclusive). this value serves as a way to set a time limit for the simple reason that
        // we cannot wait for an infinite amount of time, and has nothing to do with the fact whether or not we end up with better/worse time
        // or if we want to accept or not accept better/worse times.
        int maxTimeLimit = m_bestTime;
        if (!m_customStopTimeDeltaIsIgnored) {
            maxTimeLimit += int(m_customStopTimeDelta);
        }

        if (targetReached) {
            if (!m_wasBaseRunFound) {
                print("[Initial phase] Found new base run with time: " +  (tickTime-10) + " sec", Severity::Success);
                m_wasBaseRunFound = true;
                m_bestTime = tickTime - 10;
                
                // check if best time ever was driven
                if (m_bestTime < m_bestTimeEver) {
                    m_bestTimeEver = m_bestTime;
                    m_Manager.m_bfController.SaveSolutionToFile();
                }
            }

            if (m_customStopTimeDeltaUseOnlyOnce && !m_customStopTimeDeltaIsIgnored) {
                m_customStopTimeDeltaIsIgnored = true;
                // TODO: the variable below needs to be updated in more automatic ways
                m_canAcceptWorseTimes = m_canAcceptWorseTimes && (m_customStopTimeDelta <= 0.0);
            }

            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        if (tickTime > maxTimeLimit) {
            if (!m_wasBaseRunFound) {
                print("[Initial phase] Base run did not reach target, starting search for a base run..", Severity::Info);
            } else {
                // initial usually can only not reach the target once, and future initial phases will hit it, however i decided that if one were to change
                // the position of the trigger during bruteforce, the target may not be reached anymore in initial phase, so we will allow the bruteforce
                // to find yet another base run again
                print("[Initial phase] Base run could not reach the target anymore, despite previously having reached it. Some bruteforcing condition must have changed. Starting search for a base run..", Severity::Info);
                m_wasBaseRunFound = false;
            }
            
            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        response.Decision = BFEvaluationDecision::DoNothing;
    }

    void HandleSearchPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        int tickTime = simManager.TickTime;

        bool targetReached = false;
        switch (m_Manager.m_bfController.m_targetType) {
            case TargetType::Finish:
                targetReached = simManager.PlayerInfo.RaceFinished;
                break;
            case TargetType::Checkpoint:
                targetReached = simManager.PlayerInfo.CurCheckpointCount == m_Manager.m_bfController.m_targetId;
                break;
            case TargetType::Trigger:
                targetReached = GetTriggerByIndex(m_Manager.m_bfController.m_targetId - 1).ContainsPoint(simManager.Dyna.CurrentState.Location.Position);
                break;
        }

        // see previous usages of this variable for more info
        int maxTimeLimit = m_bestTime;
        if (!m_customStopTimeDeltaIsIgnored) {
            maxTimeLimit += int(m_customStopTimeDelta);
        }

        if (targetReached) {
            if (tickTime > maxTimeLimit) {
                response.Decision = BFEvaluationDecision::Reject;
                return;
            }

            int newTime = tickTime - 10;
            int previousBestTime = m_bestTime;

            // handle worse result acceptance probability
            if (m_canAcceptWorseTimes && newTime > previousBestTime) {
                if (Math::Rand(0.0f, 1.0f) > m_worseResultAcceptanceProbability) {
                    response.Decision = BFEvaluationDecision::Reject;
                    return;
                }
            }

            // anything below this point means we will accept the new time
            
            if (m_customStopTimeDeltaUseOnlyOnce && !m_customStopTimeDeltaIsIgnored) {
                m_customStopTimeDeltaIsIgnored = true;
                // TODO: this variable below needs to be updated in more automatic ways
                m_canAcceptWorseTimes = m_canAcceptWorseTimes && (m_customStopTimeDelta <= 0.0);
            }
            
            if (!m_wasBaseRunFound) {
                print("[Search phase] Found new base run with time: " +  newTime + " sec", Severity::Success);
                m_wasBaseRunFound = true;
            } else {
                string message = "[AS] Found";
                // higher or equal can only occur if settings are set up in such a way that worse (or equal) times are allowed to be found
                if (newTime < previousBestTime) {
                    message += " lower ";
                } else if (newTime == previousBestTime) {
                    message += " equal ";
                } else {
                    message += " higher ";
                }
                message += "time: " + Text::FormatInt(newTime);
                print(message, Severity::Success);
            }
            
            m_bestTime = newTime;

            // check if best time ever was driven
            if (m_bestTime < m_bestTimeEver) {
                m_bestTimeEver = m_bestTime;
                m_Manager.m_bfController.SaveSolutionToFile();
            }

            m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + newTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)

            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        if (tickTime > maxTimeLimit) {
            response.Decision = BFEvaluationDecision::Reject;
            return;
        }
    }
}

namespace PreciseTime {
    double bestPreciseTime; // best precise time the bf found so far
    double bestPreciseTimeEver; // keeps track for the best precise time ever reached, useful for bf that allows for worse times to be found
    bool isEstimating = false;
    uint64 coeffMin = 0;
    uint64 coeffMax = 18446744073709551615; 
    SimulationState@ originalStateBeforeTargetHit;

    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        int tickTime = simManager.TickTime;

        bool targetReached = false;
        switch (m_Manager.m_bfController.m_targetType) {
            case TargetType::Finish:
                targetReached = simManager.PlayerInfo.RaceFinished;
                break;
            case TargetType::Checkpoint:
                targetReached = simManager.PlayerInfo.CurCheckpointCount == m_Manager.m_bfController.m_targetId;
                break;
            case TargetType::Trigger:
                targetReached = GetTriggerByIndex(m_Manager.m_bfController.m_targetId - 1).ContainsPoint(simManager.Dyna.CurrentState.Location.Position);
                break;
        }

        int maxTimeLimit = m_bestTime;
        if (!m_customStopTimeDeltaIsIgnored) {
            maxTimeLimit += int(m_customStopTimeDelta);
        }

        if (targetReached) {
            if (!m_wasBaseRunFound) {
                print("[Initial phase] Found new base run with time: " +  (tickTime-10) + " sec", Severity::Success);
                m_wasBaseRunFound = true;
                m_bestTime = tickTime - 10;
                PreciseTime::bestPreciseTime = (m_bestTime / 1000.0) + 0.01;
                
                // check if best time ever was driven
                if (m_bestTime < m_bestTimeEver) {
                    m_bestTimeEver = m_bestTime;
                    m_Manager.m_bfController.SaveSolutionToFile();
                }
            }

            if (m_customStopTimeDeltaUseOnlyOnce && !m_customStopTimeDeltaIsIgnored) {
                m_customStopTimeDeltaIsIgnored = true;
                // TODO: the variable below needs to be updated in more automatic ways
                m_canAcceptWorseTimes = m_canAcceptWorseTimes && (m_customStopTimeDelta <= 0.0);
            }

            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        if (tickTime > maxTimeLimit) {
            if (!m_wasBaseRunFound) {
                print("[Initial phase] Base run did not reach target, starting search for a base run..", Severity::Info);
            } else {
                // initial usually can only not reach the target once, and future initial phases will hit it, however i decided that if one were to change
                // the position of the trigger during bruteforce, the target may not be reached anymore in initial phase, so we will allow the bruteforce
                // to find yet another base run again
                print("[Initial phase] Base run could not reach the target anymore, despite previously having reached it. Some bruteforcing condition must have changed. Starting search for a base run..", Severity::Info);
                m_wasBaseRunFound = false;
            }
            
            response.Decision = BFEvaluationDecision::Accept;
            return;
        }

        response.Decision = BFEvaluationDecision::DoNothing;
    }

    void HandleSearchPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, const BFEvaluationInfo&in info) {
        int tickTime = simManager.TickTime;

        bool targetReached = false;
        switch (m_Manager.m_bfController.m_targetType) {
            case TargetType::Finish:
                targetReached = simManager.PlayerInfo.RaceFinished;
                break;
            case TargetType::Checkpoint:
                targetReached = simManager.PlayerInfo.CurCheckpointCount == m_Manager.m_bfController.m_targetId;
                break;
            case TargetType::Trigger:
                targetReached = GetTriggerByIndex(m_Manager.m_bfController.m_targetId - 1).ContainsPoint(simManager.Dyna.CurrentState.Location.Position);
                break;
        }

        // see previous usages of this variable for more info
        int maxTimeLimit = m_bestTime;
        if (!m_customStopTimeDeltaIsIgnored) {
            maxTimeLimit += int(m_customStopTimeDelta);
        }

        if (!PreciseTime::isEstimating) {
            if (!targetReached) {
                if (tickTime > maxTimeLimit) {
                    response.Decision = BFEvaluationDecision::Reject;
                    return;
                }

                @PreciseTime::originalStateBeforeTargetHit = simManager.SaveState();
                response.Decision = BFEvaluationDecision::DoNothing;
                return;
            } else {
                PreciseTime::isEstimating = true;
            }
        } else {
            if (targetReached) {
                PreciseTime::coeffMax = PreciseTime::coeffMin + (PreciseTime::coeffMax - PreciseTime::coeffMin) / 2;
            } else {
                PreciseTime::coeffMin = PreciseTime::coeffMin + (PreciseTime::coeffMax - PreciseTime::coeffMin) / 2;
            }
        }

        simManager.RewindToState(PreciseTime::originalStateBeforeTargetHit);
        
        uint64 currentCoeff = PreciseTime::coeffMin + (PreciseTime::coeffMax - PreciseTime::coeffMin) / 2;
        double currentCoeffPercentage = currentCoeff / 18446744073709551615.0;

        if (PreciseTime::coeffMax - PreciseTime::coeffMin > m_preciseTimePrecision) {
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
        PreciseTime::isEstimating = false;
        PreciseTime::coeffMin = 0;
        PreciseTime::coeffMax = 18446744073709551615;

        double foundPreciseTime = (simManager.RaceTime / 1000.0) + (currentCoeffPercentage / 100.0);
        double previousBestPreciseTime = PreciseTime::bestPreciseTime;

        // see previous usages of this variable for more info (maxTimeLimit)
        double maxPreciseTimeLimit = previousBestPreciseTime;
        if (!m_customStopTimeDeltaIsIgnored) {
            maxPreciseTimeLimit += (m_customStopTimeDelta / 1000.0);
        }

        if (foundPreciseTime >= maxPreciseTimeLimit) {
            response.Decision = BFEvaluationDecision::Reject;
            return;
        }

        // handle worse result acceptance probability
        if (m_canAcceptWorseTimes && foundPreciseTime > previousBestPreciseTime) {
            if (Math::Rand(0.0f, 1.0f) > m_worseResultAcceptanceProbability) {
                response.Decision = BFEvaluationDecision::Reject;
                return;
            }
        }

        // anything below this point means we will accept the new time

        if (m_customStopTimeDeltaUseOnlyOnce && !m_customStopTimeDeltaIsIgnored) {
            m_customStopTimeDeltaIsIgnored = true;
            // TODO: this variable below needs to be updated in more automatic ways
            m_canAcceptWorseTimes = m_canAcceptWorseTimes && (m_customStopTimeDelta <= 0.0);
        }

        if (!m_wasBaseRunFound) {
            print("[Search phase] Found new base run with precise time: " +  DecimalFormatted(foundPreciseTime, 16) + " sec", Severity::Success);
            m_wasBaseRunFound = true;
        } else {
            string message = "[AS] Found";
            // higher or equal can only occur if settings are set up in such a way that worse (or equal) times are allowed to be found
            if (foundPreciseTime < previousBestPreciseTime) {
                message += " lower ";
            } else if (foundPreciseTime == previousBestPreciseTime) {
                message += " equal ";
            } else {
                message += " higher ";
            }
            message += "precise time: " + DecimalFormatted(foundPreciseTime, 16);
            print(message, Severity::Success);
        }

        PreciseTime::bestPreciseTime = foundPreciseTime;
        m_bestTime = int(Math::Floor(PreciseTime::bestPreciseTime * 100.0)) * 10;
            
        // check if best time ever was driven
        if (PreciseTime::bestPreciseTime < PreciseTime::bestPreciseTimeEver) {
            PreciseTime::bestPreciseTimeEver = PreciseTime::bestPreciseTime;
            m_Manager.m_bfController.SaveSolutionToFile();
        }
        if (m_bestTime < m_bestTimeEver) {
            m_bestTimeEver = m_bestTime;
        }

        m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)

        response.Decision = BFEvaluationDecision::Accept;
    }
}

// general settings that can be updated during our outside of bruteforce and can be called at any point in time
void UpdateSettings() {
    SimulationManager@ simManager = m_Manager.m_simManager;

    // m_target, m_targetType, m_targetId. only check this when bruteforce is inactive when updating settings, the bruteforce controller will have
    // additional checks for this by itself
    if (@simManager == null || !m_Manager.m_bfController.active) {
        // string for the target used for console settings
        m_Manager.m_bfController.m_target = GetVariableString("kim_bf_target");
        // target as enum for bruteforce
        if (m_Manager.m_bfController.m_target == "finish") {
            m_Manager.m_bfController.m_targetType = TargetType::Finish;
        } else if (m_Manager.m_bfController.m_target == "checkpoint") {
            m_Manager.m_bfController.m_targetType = TargetType::Checkpoint;
        } else if (m_Manager.m_bfController.m_target == "trigger") {
            m_Manager.m_bfController.m_targetType = TargetType::Trigger;
        } else {
            // reset it to finish if it was invalid
            m_Manager.m_bfController.m_target = targetNames[0];
            m_Manager.m_bfController.m_targetType = TargetType(0);
            SetVariable("kim_bf_target", targetNames[0]);
        }

        // m_targetId
        uint targetId = uint(Math::Max(GetVariableDouble("kim_bf_target_id"), 1.0));

        // check if target id is valid
        switch (m_Manager.m_bfController.m_targetType) {
            case TargetType::Finish:
                // no need to check anything
                break;
            case TargetType::Checkpoint:
                // nothing can be done for checkpoints, we are not on a map
                break; 
            case TargetType::Trigger:
                // we can check for triggers because those are built into TMI
                if (targetId > GetTriggerIds().Length) {
                    targetId = GetTriggerIds().Length;
                }
                break;
        }
        m_Manager.m_bfController.m_targetId = targetId;
        SetVariable("kim_bf_target_id", targetId);
    }

    // precise time
    m_usePreciseTime = GetVariableBool("kim_bf_use_precise_time");
	if (m_usePreciseTime) {
		// precise time precision
		m_preciseTimePrecision = uint(Math::Max(1, int(GetVariableDouble("kim_bf_precise_time_precision"))));
        SetVariable("kim_bf_precise_time_precision", m_preciseTimePrecision);
	}

    // modify type
    m_modifyType = GetVariableString("kim_bf_modify_type");

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
	m_modifySteeringMinAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_min_amount"))));
    m_modifySteeringMaxAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_steering_max_amount"))));
    m_modifySteeringMinAmount = Math::Min(m_modifySteeringMinAmount, m_modifySteeringMaxAmount);
    SetVariable("kim_bf_modify_steering_min_amount", m_modifySteeringMinAmount);
    SetVariable("kim_bf_modify_steering_max_amount", m_modifySteeringMaxAmount);

    m_modifyAccelerationMinAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_min_amount"))));
    m_modifyAccelerationMaxAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_acceleration_max_amount"))));
    m_modifyAccelerationMinAmount = Math::Min(m_modifyAccelerationMinAmount, m_modifyAccelerationMaxAmount);
    SetVariable("kim_bf_modify_acceleration_min_amount", m_modifyAccelerationMinAmount);
    SetVariable("kim_bf_modify_acceleration_max_amount", m_modifyAccelerationMaxAmount);

    m_modifyBrakeMinAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_min_amount"))));
    m_modifyBrakeMaxAmount = uint(Math::Max(0, int(GetVariableDouble("kim_bf_modify_brake_max_amount"))));
    m_modifyBrakeMinAmount = Math::Min(m_modifyBrakeMinAmount, m_modifyBrakeMaxAmount);
    SetVariable("kim_bf_modify_brake_min_amount", m_modifyBrakeMinAmount);
    SetVariable("kim_bf_modify_brake_max_amount", m_modifyBrakeMaxAmount);
    
    // input modifications percentage
    m_modifySteeringMinPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_steering_min_percentage")), 0.0, 100.0));
    m_modifySteeringMaxPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_steering_max_percentage")), 0.0, 100.0));
    m_modifySteeringMinPercentage = Math::Min(m_modifySteeringMinPercentage, m_modifySteeringMaxPercentage);
    SetVariable("kim_bf_modify_steering_min_percentage", m_modifySteeringMinPercentage);
    SetVariable("kim_bf_modify_steering_max_percentage", m_modifySteeringMaxPercentage);

    m_modifyAccelerationMinPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_acceleration_min_percentage")), 0.0, 100.0));
    m_modifyAccelerationMaxPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_acceleration_max_percentage")), 0.0, 100.0));
    m_modifyAccelerationMinPercentage = Math::Min(m_modifyAccelerationMinPercentage, m_modifyAccelerationMaxPercentage);
    SetVariable("kim_bf_modify_acceleration_min_percentage", m_modifyAccelerationMinPercentage);
    SetVariable("kim_bf_modify_acceleration_max_percentage", m_modifyAccelerationMaxPercentage);

    m_modifyBrakeMinPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_brake_min_percentage")), 0.0, 100.0));
    m_modifyBrakeMaxPercentage = double(Math::Clamp(float(GetVariableDouble("kim_bf_modify_brake_max_percentage")), 0.0, 100.0));
    m_modifyBrakeMinPercentage = Math::Min(m_modifyBrakeMinPercentage, m_modifyBrakeMaxPercentage);
    SetVariable("kim_bf_modify_brake_min_percentage", m_modifyBrakeMinPercentage);
    SetVariable("kim_bf_modify_brake_max_percentage", m_modifyBrakeMaxPercentage);


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

    // use custom stop time delta only once
    bool previousCustomStopTimeDeltaUseOnlyOnce = m_customStopTimeDeltaUseOnlyOnce;
    m_customStopTimeDeltaUseOnlyOnce = GetVariableBool("kim_bf_custom_stop_time_delta_use_only_once");
    // custom stop time delta
    m_customStopTimeDelta = GetVariableDouble("kim_bf_custom_stop_time_delta");
	if (!m_usePreciseTime) {
		m_customStopTimeDelta = double(Math::Round(m_customStopTimeDelta * 100.0) * 10.0);
	} else {
		m_customStopTimeDelta = double(m_customStopTimeDelta * 1000.0);
	}
    // check if the m_customStopTimeDeltaUseOnlyOnce value has changed
    if (previousCustomStopTimeDeltaUseOnlyOnce != m_customStopTimeDeltaUseOnlyOnce) {
        m_customStopTimeDeltaIsIgnored = false;
    }

    if (@simManager != null && m_Manager.m_bfController.active) {
        m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
    }

    // accept worse times chance
    m_worseResultAcceptanceProbability = Math::Clamp(float(GetVariableDouble("kim_bf_worse_result_acceptance_probability")), 0.00000001f, 1.0f);

    // logging
    m_useInfoLogging = GetVariableBool("kim_bf_use_info_logging");
    m_useIterLogging = GetVariableBool("kim_bf_use_iter_logging");
    m_loggingInterval = Math::Clamp(uint(GetVariableDouble("kim_bf_logging_interval")), 1, 1000);


    /* helper vars */

    // specify any conditions that could lead to a worse time here
    m_canAcceptWorseTimes = m_customStopTimeDelta > 0.0;


    m_useLiveDebugging = GetVariableBool("kim_bf_use_live_debugging");
}

/* SIMULATION MANAGEMENT */

class BruteforceController {
    BruteforceController() {}
    ~BruteforceController() {}

    // reset variables bruteforce needs
    void SetBruteforceVariables(SimulationManager@ simManager) {
        // General Variables
        m_wasBaseRunFound = false;
        m_bestTime = simManager.EventsDuration; // original time of the replay
        m_bestTimeEver = m_bestTime;

        m_iterations = 0;
        m_iterationsCounter = 0;
        m_iterationsPerSecond = 0.0f;
        m_lastIterationsPerSecondUpdate = 0.0f;

        // PreciseTime Variables
        PreciseTime::isEstimating = false;
        PreciseTime::coeffMin = 0;
        PreciseTime::coeffMax = 18446744073709551615;
        PreciseTime::bestPreciseTime = double(m_bestTime + 10) / 1000.0; // best precise time the bf found so far
        // PreciseTime helper variables
        PreciseTime::bestPreciseTimeEver = PreciseTime::bestPreciseTime;

        // Bruteforce Variables
        m_resultFileName = GetVariableString("kim_bf_result_file_name");


        // m_target, m_targetType, m_targetId
        m_target = GetVariableString("kim_bf_target");
        // target as enum for bruteforce
        if (m_target == "finish") {
            m_targetType = TargetType::Finish;
        } else if (m_target == "checkpoint") {
            m_targetType = TargetType::Checkpoint;
        } else if (m_target == "trigger") {
            m_targetType = TargetType::Trigger;
        } else {
            print("[AS] Invalid bruteforce target: " + m_target + ", stopping bruteforce..", Severity::Error);
            OnSimulationEnd(simManager);
            return;
        }

        // in case of checkpoint or trigger, the index of the target
        uint targetId = uint(Math::Max(GetVariableDouble("kim_bf_target_id"), 1.0));

        // check if target id is valid
        switch (m_targetType) {
            case TargetType::Finish:
                // no need to check anything
                break;
            case TargetType::Checkpoint:
            {
                uint checkpointCount = simManager.PlayerInfo.Checkpoints.Length;
                if (targetId > checkpointCount) {
                    print("[AS] Checkpoint with target id " + targetId + " does not exist on this map, change the target id in settings to fix this issue. stopping bruteforce..", Severity::Error);
                    OnSimulationEnd(simManager);
                    return;
                }
                break;
            }
            case TargetType::Trigger:
            {
                uint triggerCount = GetTriggerIds().Length;
                if (triggerCount == 0) {
                    print("[AS] Cannot bruteforce for trigger target, no triggers were found. stopping bruteforce..", Severity::Error);
                    OnSimulationEnd(simManager);
                    return;
                }
                // if too high target id is specified, set to highest poss
                if (targetId > triggerCount) {
                    print("[AS] Trigger with target id " + targetId + " does not exist, change the target id in settings to fix this issue. stopping bruteforce..", Severity::Error);
                    OnSimulationEnd(simManager);
                    return;
                }
                break;
            }
        }

        m_targetId = targetId;


        // fill missing inputs
        m_useFillMissingInputsSteering = GetVariableBool("kim_bf_use_fill_missing_inputs_steering");
        m_useFillMissingInputsAcceleration = GetVariableBool("kim_bf_use_fill_missing_inputs_acceleration");
        m_useFillMissingInputsBrake = GetVariableBool("kim_bf_use_fill_missing_inputs_brake");


        // for m_customStopTimeDelta / m_customStopTimeDeltaUseOnlyOnce
        m_customStopTimeDeltaIsIgnored = false;
    }
    
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
        SetBruteforceVariables(simManager);
        UpdateSettings();

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

        // set the simulation time limit to make the game quit the simulation right away, or else we'll have to wait all the way until the end of the replay..
        simManager.SetSimulationTimeLimit(0.0);
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

        uint modifySteeringMinTime = Math::Max(0, m_modifySteeringMinTime);
        uint modifySteeringMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifySteeringMaxTime = m_modifySteeringMaxTime == 0 ? modifySteeringMaxTime : Math::Min(modifySteeringMaxTime, m_modifySteeringMaxTime);

        uint modifyAccelerationMinTime = Math::Max(0, m_modifyAccelerationMinTime);
        uint modifyAccelerationMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifyAccelerationMaxTime = m_modifyAccelerationMaxTime == 0 ? modifyAccelerationMaxTime : Math::Min(modifyAccelerationMaxTime, m_modifyAccelerationMaxTime);

        uint modifyBrakeMinTime = Math::Max(0, m_modifyBrakeMinTime);
        uint modifyBrakeMaxTime = m_bestTime + int(m_customStopTimeDelta);
        modifyBrakeMaxTime = m_modifyBrakeMaxTime == 0 ? modifyBrakeMaxTime : Math::Min(modifyBrakeMaxTime, m_modifyBrakeMaxTime);

        // input modifications based on m_modifyType
        if (m_modifyType == "amount") {
            uint steerValuesModified = 0;
            uint accelerationValuesModified = 0;
            uint brakeValuesModified = 0;

            uint maxSteeringModifyAmount = Math::Rand(m_modifySteeringMinAmount, m_modifySteeringMaxAmount);
            uint maxAccelerationModifyAmount = Math::Rand(m_modifyAccelerationMinAmount, m_modifyAccelerationMaxAmount);
            uint maxBrakeModifyAmount = Math::Rand(m_modifyBrakeMinAmount, m_modifyBrakeMaxAmount);

            // we either modify an existing value or add a new one
            // we do this until we have reached the max amount of modifications

            // steering
            while (steerValuesModified < maxSteeringModifyAmount) {
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
            while (accelerationValuesModified < maxAccelerationModifyAmount) {
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
            while (brakeValuesModified < maxBrakeModifyAmount) {
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
        } else if (m_modifyType == "percentage") {
            double steeringModifyPercentage = double(Math::Rand(float(m_modifySteeringMinPercentage), float(m_modifySteeringMaxPercentage)));
            double accelerationModifyPercentage = double(Math::Rand(float(m_modifyAccelerationMinPercentage), float(m_modifyAccelerationMaxPercentage)));
            double brakeModifyPercentage = double(Math::Rand(float(m_modifyBrakeMinPercentage), float(m_modifyBrakeMaxPercentage)));

            // we iterate from m_modifyMinTime to m_modifyMaxTime, and for each tick we check if we want to modify something based on the percentage,
            // and then we either modify the value if there is one, or add a new one if there is none

            // TODO: remove later, for debugging
            uint modifiedvalues = 0;

            // steering
            for (uint modifyTime = modifySteeringMinTime; modifyTime < modifySteeringMaxTime; modifyTime += 10) {
                if (double(Math::Rand(0.0f, 100.0f)) > steeringModifyPercentage) {
                    continue;
                }
                modifiedvalues++;

                // check if there is already a value at that time
                auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Steer);
                // if there is no value at that time, add a new one
                if (modifyIndex.Length == 0) {
                    // add a new value
                    int newValue = Math::Rand(-m_modifySteeringMaxDiff/2, m_modifySteeringMaxDiff/2);
                    inputBuffer.Add(modifyTime, InputType::Steer, newValue);
                    
                    lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);

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
            for (uint modifyTime = modifyAccelerationMinTime; modifyTime < modifyAccelerationMaxTime; modifyTime += 10) {
                if (double(Math::Rand(0.0f, 100.0f)) > accelerationModifyPercentage) {
                    continue;
                }

                // check if there is already a value at that time
                auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Up);
                // if there is no value at that time, add a new one
                if (modifyIndex.Length == 0) {
                    // add a new value
                    int newValue = Math::Rand(0, 1);
                    inputBuffer.Add(modifyTime, InputType::Up, newValue);
                    
                    lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);

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
            for (uint modifyTime = modifyBrakeMinTime; modifyTime < modifyBrakeMaxTime; modifyTime += 10) {
                if (double(Math::Rand(0.0f, 100.0f)) > brakeModifyPercentage) {
                    continue;
                }

                // check if there is already a value at that time
                auto modifyIndex = inputBuffer.Find(modifyTime, InputType::Down);
                // if there is no value at that time, add a new one
                if (modifyIndex.Length == 0) {
                    // add a new value
                    int newValue = Math::Rand(0, 1);
                    inputBuffer.Add(modifyTime, InputType::Down, newValue);
                    
                    lowestTimeModified = Math::Min(lowestTimeModified, modifyTime);

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
        }

        if (lowestTimeModified == 0 || lowestTimeModified == 2147483647) {
            m_rewindIndex = 0;
        } else {
            m_rewindIndex = lowestTimeModified / 10 - 1;
        }

        if (m_originalSimulationStates[m_originalSimulationStates.Length-1].PlayerInfo.RaceTime < int(m_rewindIndex * 10)) {
            print("[AS] Rewind time is higher than highest saved simulation state, this can happen when custom stop time delta is > 0.0 and inputs were generated that occurred beyond the finish time that was driven during the initial phase. RandomNeighbour will be called again. If this keeps happening, lower the custom stop time.", Severity::Warning);
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

    void RestoreInputBuffer() {
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
            PreciseTime::HandleSearchPhase(m_simManager, response, info);
            return;
        } else {
            NormalTime::HandleSearchPhase(m_simManager, response, info);
            return;
        }
    }

    void HandleInitialPhase(SimulationManager@ simManager, BFEvaluationResponse&out response, BFEvaluationInfo&in info) {
        if (m_usePreciseTime) {
            PreciseTime::HandleInitialPhase(m_simManager, response, info);
            return;
        } else {
            NormalTime::HandleInitialPhase(m_simManager, response, info);
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

    void SaveSolutionToFile() {
        // m_commandList.Content = simManager.InputEvents.ToCommandsText();
        // only save if the time we found is the best time ever, currently also saves when an equal time was found and accepted
        if (!m_usePreciseTime) {
            if (m_bestTime == m_bestTimeEver) {
                m_commandList.Content = "# Found time: " + m_bestTime + ", iterations: " + m_iterations + "\n";
                m_commandList.Content += m_Manager.m_simManager.InputEvents.ToCommandsText(InputFormatFlags(3));
                m_commandList.Save(m_resultFileName);
            }
        } else {
            if (PreciseTime::bestPreciseTime == PreciseTime::bestPreciseTimeEver) {
                m_commandList.Content = "# Found precise time: " + DecimalFormatted(PreciseTime::bestPreciseTime, 16) + ", iterations: " + m_iterations + "\n";
                m_commandList.Content += m_Manager.m_simManager.InputEvents.ToCommandsText(InputFormatFlags(3));
                m_commandList.Save(m_resultFileName);
            }
        }
    }

    // informational functions
    void PrintBruteforceInfo() {
        if (!m_useInfoLogging && !m_useIterLogging) {
            return;
        }
        
        string message = "[AS] ";

        if (m_useInfoLogging) {
            if (m_usePreciseTime) {
                message += "best precise time: " + DecimalFormatted(PreciseTime::bestPreciseTime, 16);
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

        if (m_iterationsCounter % m_loggingInterval == 0) {
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
    BFPhase m_phase = BFPhase::Initial;

    // initialized as "finish"
    string m_target = targetNames[0];
    TargetType m_targetType = TargetType(0);
    uint m_targetId = 1; // used for checkpoint/trigger targets, id is index+1

    array<SimulationState@> m_originalSimulationStates = {};
    array<TM::InputEvent> m_originalInputEvents; 

    private uint m_rewindIndex = 0;
}

class Manager {
    Manager() {
        @m_bfController = BruteforceController();
    }
    ~Manager() {}

    void OnSimulationBegin(SimulationManager@ simManager) {
        @m_simManager = simManager;
        m_simManager.RemoveStateValidation();
        m_bfController.OnSimulationBegin(simManager);
    }

    void OnSimulationStep(SimulationManager@ simManager, bool userCancelled) {
        if (userCancelled) {
            m_bfController.OnSimulationEnd(simManager);
            return;
        }

        m_bfController.OnSimulationStep(simManager);
    }

    void OnSimulationEnd(SimulationManager@ simManager, uint result) {
        m_bfController.OnSimulationEnd(simManager);
    }

    void OnCheckpointCountChanged(SimulationManager@ simManager, int count, int target) {
        m_bfController.OnCheckpointCountChanged(simManager, count, target);
    }

    SimulationManager@ m_simManager;
    BruteforceController@ m_bfController;
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
    if (!m_Manager.m_bfController.active) {
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
    
    if (!m_Manager.m_bfController.active) {
        m_Manager.m_bfController.m_target = GetVariableString("kim_bf_target");
        if (UI::BeginCombo("##target", m_Manager.m_bfController.m_target)) {
            for (uint i = 0; i < targetNames.Length; i++) {
                bool isSelected = m_Manager.m_bfController.m_target == targetNames[i];
                if (UI::Selectable(targetNames[i], isSelected)) {
                    m_Manager.m_bfController.m_target = targetNames[i];
                    SetVariable("kim_bf_target", targetNames[i]);
                    m_Manager.m_bfController.m_targetType = TargetType(i);
                }
            }
            UI::EndCombo();
        }
    } else {
        UI::Text(m_Manager.m_bfController.m_target);
    }

    // if target is checkpoint or trigger, show index
    if (m_Manager.m_bfController.m_targetType == TargetType::Checkpoint || m_Manager.m_bfController.m_targetType == TargetType::Trigger) {
        UI::SameLine();
        UI::Text("Index");
        UI::SameLine();
        if (!m_Manager.m_bfController.active) {
            // target id is index+1, 0 will be used for invalid or unused in case of finish
            uint targetId = uint(Math::Max(UI::InputIntVar("##targetid", "kim_bf_target_id", 1), 1));
            // check if target id is valid
            switch (m_Manager.m_bfController.m_targetType) {
                case TargetType::Checkpoint:
                    // we cant check for checkpoint count because we havent loaded a map, simple set the value, an error will be given on bruteforce start
                    SetVariable("kim_bf_target_id", targetId);
                    break;
                case TargetType::Trigger:
                {
                    uint triggerCount = GetTriggerIds().Length;
                    if (triggerCount == 0) {
                        UI::Text("No triggers found. Make sure to add triggers");
                    } else if (targetId > triggerCount) {
                        targetId = triggerCount;
                    }
                    m_Manager.m_bfController.m_targetId = targetId;
                    SetVariable("kim_bf_target_id", targetId);
                    break;
                }
            }
        } else {
            UI::Text("" + m_Manager.m_bfController.m_targetId);
        }
    }

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

    UI::PushItemWidth(120);
    UI::Text("Input Modifications:");
    // can be a simple value based range amount or percentage based range
    UI::SameLine();

    // kim_bf_modify_type
    m_modifyType = GetVariableString("kim_bf_modify_type");
    if (UI::BeginCombo("##modifytype", m_modifyType)) {
        for (uint i = 0; i < modifyTypes.Length; i++) {
            bool isSelected = m_modifyType == modifyTypes[i];
            if (UI::Selectable(modifyTypes[i], isSelected)) {
                m_modifyType = modifyTypes[i];
                SetVariable("kim_bf_modify_type", modifyTypes[i]);
            }
        }
        UI::EndCombo();
    }

    if (m_modifyType == "amount") {
        // kim_bf_modify_steering_min_amount, kim_bf_modify_steering_max_amount,
        // kim_bf_modify_acceleration_min_amount, kim_bf_modify_acceleration_max_amount,
        // kim_bf_modify_brake_min_amount, kim_bf_modify_brake_max_amount
        int modifySteeringMinAmount = Math::Max(UI::InputIntVar("Steer Min Amount        ", "kim_bf_modify_steering_min_amount", 1), 0);
        SetVariable("kim_bf_modify_steering_min_amount", modifySteeringMinAmount);
        if (uint(modifySteeringMinAmount) > m_modifySteeringMaxAmount) {
            SetVariable("kim_bf_modify_steering_max_amount", modifySteeringMinAmount);
        }
        UI::SameLine();
        int modifySteeringMaxAmount = Math::Max(UI::InputIntVar("Steer Max Amount", "kim_bf_modify_steering_max_amount", 1), 0);
        SetVariable("kim_bf_modify_steering_max_amount", modifySteeringMaxAmount);
        if (uint(modifySteeringMaxAmount) < m_modifySteeringMinAmount) {
            SetVariable("kim_bf_modify_steering_min_amount", modifySteeringMaxAmount);
        }
        m_modifySteeringMinAmount = modifySteeringMinAmount;
        m_modifySteeringMaxAmount = modifySteeringMaxAmount;

        int modifyAccelerationMinAmount = Math::Max(UI::InputIntVar("Accel Min Amount        ", "kim_bf_modify_acceleration_min_amount", 1), 0);
        SetVariable("kim_bf_modify_acceleration_min_amount", modifyAccelerationMinAmount);
        if (uint(modifyAccelerationMinAmount) > m_modifyAccelerationMaxAmount) {
            SetVariable("kim_bf_modify_acceleration_max_amount", modifyAccelerationMinAmount);
        }
        UI::SameLine();
        int modifyAccelerationMaxAmount = Math::Max(UI::InputIntVar("Accel Max Amount", "kim_bf_modify_acceleration_max_amount", 1), 0);
        SetVariable("kim_bf_modify_acceleration_max_amount", modifyAccelerationMaxAmount);
        if (uint(modifyAccelerationMaxAmount) < m_modifyAccelerationMinAmount) {
            SetVariable("kim_bf_modify_acceleration_min_amount", modifyAccelerationMaxAmount);
        }
        m_modifyAccelerationMinAmount = modifyAccelerationMinAmount;
        m_modifyAccelerationMaxAmount = modifyAccelerationMaxAmount;

        int modifyBrakeMinAmount = Math::Max(UI::InputIntVar("Brake Min Amount       ", "kim_bf_modify_brake_min_amount", 1), 0);
        SetVariable("kim_bf_modify_brake_min_amount", modifyBrakeMinAmount);
        if (uint(modifyBrakeMinAmount) > m_modifyBrakeMaxAmount) {
            SetVariable("kim_bf_modify_brake_max_amount", modifyBrakeMinAmount);
        }
        UI::SameLine();
        int modifyBrakeMaxAmount = Math::Max(UI::InputIntVar("Brake Max Amount", "kim_bf_modify_brake_max_amount", 1), 0);
        SetVariable("kim_bf_modify_brake_max_amount", modifyBrakeMaxAmount);
        if (uint(modifyBrakeMaxAmount) < m_modifyBrakeMinAmount) {
            SetVariable("kim_bf_modify_brake_min_amount", modifyBrakeMaxAmount);
        }
        m_modifyBrakeMinAmount = modifyBrakeMinAmount;
        m_modifyBrakeMaxAmount = modifyBrakeMaxAmount;

        if (m_modifySteeringMaxAmount == 0 && m_modifyAccelerationMaxAmount == 0 && m_modifyBrakeMaxAmount == 0) {
            UI::TextDimmed("Warning: No input modifications will be made!");
        }
        UI::TextDimmed("A random value between min/max amount is picked and that's how many inputs will be modified. Note inputs will not be modified beyond the input max time.");
    } else if (m_modifyType == "percentage") {
        // kim_bf_modify_steering_min_percentage, kim_bf_modify_steering_max_percentage,
        // kim_bf_modify_acceleration_min_percentage, kim_bf_modify_acceleration_max_percentage,
        // kim_bf_modify_brake_min_percentage, kim_bf_modify_brake_max_percentage
        // kim_bf_modify_type
        double modifySteeringMinPercentage = Math::Clamp(double(UI::InputFloatVar("Steer Min Percentage        ", "kim_bf_modify_steering_min_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_steering_min_percentage", modifySteeringMinPercentage);
        if (modifySteeringMinPercentage > m_modifySteeringMaxPercentage) {
            SetVariable("kim_bf_modify_steering_max_percentage", modifySteeringMinPercentage);
        }
        UI::SameLine();
        double modifySteeringMaxPercentage = Math::Clamp(double(UI::InputFloatVar("Steer Max Percentage", "kim_bf_modify_steering_max_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_steering_max_percentage", modifySteeringMaxPercentage);
        if (modifySteeringMaxPercentage < m_modifySteeringMinPercentage) {
            SetVariable("kim_bf_modify_steering_min_percentage", modifySteeringMaxPercentage);
        }
        m_modifySteeringMinPercentage = modifySteeringMinPercentage;
        m_modifySteeringMaxPercentage = modifySteeringMaxPercentage;

        double modifyAccelerationMinPercentage = Math::Clamp(double(UI::InputFloatVar("Accel Min Percentage        ", "kim_bf_modify_acceleration_min_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_acceleration_min_percentage", modifyAccelerationMinPercentage);
        if (modifyAccelerationMinPercentage > m_modifyAccelerationMaxPercentage) {
            SetVariable("kim_bf_modify_acceleration_max_percentage", modifyAccelerationMinPercentage);
        }
        UI::SameLine();
        double modifyAccelerationMaxPercentage = Math::Clamp(double(UI::InputFloatVar("Accel Max Percentage", "kim_bf_modify_acceleration_max_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_acceleration_max_percentage", modifyAccelerationMaxPercentage);
        if (modifyAccelerationMaxPercentage < m_modifyAccelerationMinPercentage) {
            SetVariable("kim_bf_modify_acceleration_min_percentage", modifyAccelerationMaxPercentage);
        }
        m_modifyAccelerationMinPercentage = modifyAccelerationMinPercentage;
        m_modifyAccelerationMaxPercentage = modifyAccelerationMaxPercentage;

        double modifyBrakeMinPercentage = Math::Clamp(double(UI::InputFloatVar("Brake Min Percentage        ", "kim_bf_modify_brake_min_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_brake_min_percentage", modifyBrakeMinPercentage);
        if (modifyBrakeMinPercentage > m_modifyBrakeMaxPercentage) {
            SetVariable("kim_bf_modify_brake_max_percentage", modifyBrakeMinPercentage);
        }
        UI::SameLine();
        double modifyBrakeMaxPercentage = Math::Clamp(double(UI::InputFloatVar("Brake Max Percentage", "kim_bf_modify_brake_max_percentage", 0.01f)), 0.0, 100.0);
        SetVariable("kim_bf_modify_brake_max_percentage", modifyBrakeMaxPercentage);
        if (modifyBrakeMaxPercentage < m_modifyBrakeMinPercentage) {
            SetVariable("kim_bf_modify_brake_min_percentage", modifyBrakeMaxPercentage);
        }
        m_modifyBrakeMinPercentage = modifyBrakeMinPercentage;
        m_modifyBrakeMaxPercentage = modifyBrakeMaxPercentage;

        if (m_modifySteeringMaxPercentage == 0.0 && m_modifyAccelerationMaxPercentage == 0.0 && m_modifyBrakeMaxPercentage == 0.0) {
            UI::TextDimmed("Warning: No input modifications will be made!");
        }
        UI::TextDimmed("A random value between min/max percentage is picked and each input in min/max time range will use that as a probability for the value to be modified.");
    }
    
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
    if (!m_Manager.m_bfController.active) {
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

    /* custom stop time */
    UI::PushItemWidth(180);
    // m_customStopTimeDeltaUseOnlyOnce
    if (!m_useLiveDebugging || !m_Manager.m_bfController.active) {
        bool previousCustomStopTimeDeltaUseOnlyOnce = m_customStopTimeDeltaUseOnlyOnce;
        m_customStopTimeDeltaUseOnlyOnce = UI::CheckboxVar("Use Custom Stop Time Delta Only Once", "kim_bf_custom_stop_time_delta_use_only_once");
        // helper var for m_customStopTimeDeltaUseOnlyOnce
        if (previousCustomStopTimeDeltaUseOnlyOnce != m_customStopTimeDeltaUseOnlyOnce) {
            // in either case we simply reset the m_customStopTimeDeltaIsIgnored value
            m_customStopTimeDeltaIsIgnored = false;
        }
    } else {
        // grey out by simulating with ✓ text
        if (m_customStopTimeDeltaUseOnlyOnce) {
            UI::Text("[✓] Use Custom Stop Time Delta Only Once");
        } else {
            UI::Text("[] Use Custom Stop Time Delta Only Once");
        }
    }
    // m_customStopTimeDelta, i use InputFloatVar because InputTimeVar doesn't allow for negative values
    auto previousCustomStopTimeDelta = m_customStopTimeDelta;
    m_customStopTimeDelta = UI::InputFloatVar("##overridestoptime", "kim_bf_custom_stop_time_delta", 0.01f);
    
    
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
        if (@m_Manager.m_simManager != null && m_Manager.m_bfController.active) {
            m_Manager.m_simManager.SetSimulationTimeLimit(int(m_customStopTimeDelta) + m_bestTime + 10010); // i add 10010 because tmi subtracts 10010 and it seems to be wrong. (also dont confuse this with the other value of 100010, thats something else)
        }
    }

    UI::TextDimmed("Allow the car to drive until +/- the current best time of the bruteforce. Example: Set it to -0.05 and it will only find improvements that are atleast 0.05 sec better than the current best time. Set it to +0.05 to accept times that are up to 0.05 sec worse, for example if you force finished and need to reach the finish again. \nExtra note: This input field only allows 3 decimals, but you can still write down more precision, the value next to it shows the actual value that will be used.");
    UI::PopItemWidth();
    
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    // kim_bf_worse_result_acceptance_probability
    UI::PushItemWidth(180);
    m_worseResultAcceptanceProbability = Math::Clamp(UI::SliderFloatVar("Worse Result Acceptance Probability", "kim_bf_worse_result_acceptance_probability", 0.00000001f, 1.0f, "%.8f"), 0.00000001f, 1.0f);
    SetVariable("kim_bf_worse_result_acceptance_probability", m_worseResultAcceptanceProbability);
    UI::TextDimmed("This will only be used for scenarios where a worse time can be driven and also get accepted, for example if the custom override delta time is positive");
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

    // kim_bf_logging_interval
    UI::PushItemWidth(180);
    m_loggingInterval = uint(Math::Clamp(UI::SliderIntVar("Logging Interval", "kim_bf_logging_interval", 1, 1000), 1, 1000));
    SetVariable("kim_bf_logging_interval", m_loggingInterval);
    UI::TextDimmed("Log to console every x iterations.");
    UI::PopItemWidth();


    // specify any conditions that could lead to a worse time here
    m_canAcceptWorseTimes = m_customStopTimeDelta > 0.0;






    /* START OF LIVE DEBUGGING */
    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));

    UI::Text("Live Debugging");
    UI::TextDimmed("This allows to view and control internal variables of the bruteforce while it is running. While debugging is turned on, access to certain settings variables will be disabled. This currently an early prototype and offers support only for the internal flag which checks if the custom stop time delta was reached once. What's the use case??? Figure it out yourself :) (Hint: lets just say changing permanent settings variables during bruteforce isn't always the best idea)");
    UI::Dummy(vec2(0, 15));

    m_useLiveDebugging = UI::CheckboxVar("Activate", "kim_bf_use_live_debugging");
    if (!m_useLiveDebugging) {
        return;
    }

    if (!m_Manager.m_bfController.active) {
        UI::TextDimmed("Live Debugging is only available while the bruteforce is running.");
        UI::Dummy(vec2(0, 15));
        return;
    }

    
    UI::Dummy(vec2(0, 30));

    // control internal variables
    UI::PushItemWidth(180);
    UI::Text("m_customStopTimeDeltaIsIgnored: " + (m_customStopTimeDeltaIsIgnored ? "true" : "false"));
    UI::SameLine();
    if (UI::Button("Reset##m_customStopTimeDeltaIsIgnored", vec2(60, 0))) {
        m_customStopTimeDeltaIsIgnored = false;
    }


    UI::Dummy(vec2(0, 15));
    UI::Separator();
    UI::Dummy(vec2(0, 15));






}

void Main() {
    @m_Manager = Manager();

    RegisterVariable("kim_bf_result_file_name", "result.txt");

    RegisterVariable("kim_bf_target", targetNames[0]); // "finish" / "checkpoint" / "trigger"
    RegisterVariable("kim_bf_target_id", 1.0); // id of target (index + 1), used for checkpoint/trigger

    RegisterVariable("kim_bf_use_precise_time", true);
    RegisterVariable("kim_bf_precise_time_precision", 1.0);

    RegisterVariable("kim_bf_modify_steering_min_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_time", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_time", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_max_time", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_time", 0.0);

    RegisterVariable("kim_bf_modify_type", modifyTypes[0]); // "amount" / "percentage"
    RegisterVariable("kim_bf_modify_steering_min_amount", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_amount", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_amount", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_amount", 1.0);
    RegisterVariable("kim_bf_modify_acceleration_max_amount", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_amount", 0.0);
    RegisterVariable("kim_bf_modify_steering_min_percentage", 0.0);
    RegisterVariable("kim_bf_modify_acceleration_min_percentage", 0.0);
    RegisterVariable("kim_bf_modify_brake_min_percentage", 0.0);
    RegisterVariable("kim_bf_modify_steering_max_percentage", 1.0);
    RegisterVariable("kim_bf_modify_acceleration_max_percentage", 0.0);
    RegisterVariable("kim_bf_modify_brake_max_percentage", 0.0);

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

    RegisterVariable("kim_bf_custom_stop_time_delta_use_only_once", false);
    RegisterVariable("kim_bf_custom_stop_time_delta", 0.0);

    RegisterVariable("kim_bf_use_info_logging", true);
    RegisterVariable("kim_bf_use_iter_logging", true);
    RegisterVariable("kim_bf_logging_interval", 200.0);

    RegisterVariable("kim_bf_worse_result_acceptance_probability", 1.0f);

    RegisterVariable("kim_bf_use_live_debugging", false);

    UpdateSettings();

    RegisterValidationHandler("kim_bf_controller", "[AS] Kim's Bruteforce Controller", BruteforceSettingsWindow);
}

PluginInfo@ GetPluginInfo() {
    auto info = PluginInfo();
    info.Name = "Kim's Bruteforce Controller";
    info.Author = "Kim";
    info.Version = "v1.3.2";
    info.Description = "General bruteforcing capabilities";
    return info;
}
