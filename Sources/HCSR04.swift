import SwiftyGPIO
import Foundation
import Dispatch

public enum HCSR04Error: Error {
    case echoSignalError                                        // check pin connections, timeout, and range
    case measuredDistanceIsOutSensorRange
    case userTimeout
    case unavailableGPIO(detail: String)
}

/// Create an instance representing the HC-SR04 hardware module
///
/// Avoiding *pin* terminology favoring GPIO## as that's what the SwiftyGPIO `.P##` enumeration cases are (vs board pin #).
/// [Raspberry Pi Pinout](https://www.raspberrypi.com/documentation/computers/os.html#gpio-pinout)
///
/// Default maximum distance comes from [the datasheet](https://cdn.sparkfun.com/datasheets/Sensors/Proximity/HCSR04.pdf)
///
open class HCSR04 {
    public typealias CentiMeters = Double
    
    public var triggerGPIO    : GPIO?                           // ultrasonic emitter sends first
    public var echoGPIO       : GPIO?                           // ultrasonic receiver then receives returned sound waves
    public var maximumDistance: CentiMeters = 400

    /// No-arg constructor, make sure to assign `triggerGPIO` and `echoGPIO` or use optional convenience constructor
    ///
    public init() {}

    /// Convenience constructor to perform initialization and configuration in a single step
    ///
    /// Treats the instance creation as uncertain, exactly what it is if the GPIOs are not available. Prefers exceptions to fatal errors that kill the
    /// entire binary, allowing this to be one library in a larger, likely headless system.  Avoids mystery crashes caused by forced unwraps.
    /// If you can create an instance of something that's misconfigured or will hard crash later with poor description, you don't really have an
    /// instance you can count on.
    ///
    public init?(board: SupportedBoard = .RaspberryPi4, trigger: GPIOName, echo: GPIOName) {
        do {
            try configure(board: board, trigger: trigger, echo: echo)
        } catch {
            print("Could not stand up an instance of HCSR04 due to: \(error)")
            return nil
        }
    }
    
    open func configure (board: SupportedBoard = .RaspberryPi4,
                         trigger: GPIOName, echo: GPIOName) throws
    {
        let gpios = SwiftyGPIO.GPIOs(for: board)

        guard let echoGPIO = gpios[echo] else {
            throw HCSR04Error.unavailableGPIO(detail: "Echo GPIO number \(echo) not available, check power and wiring")
        }
        echoGPIO.direction = .IN
        
        guard let triggerGPIO = gpios[trigger] else {
            throw HCSR04Error.unavailableGPIO(detail: "Trigger GPIO number \(echo) not available, check power and wiring")
        }
        triggerGPIO.direction = .OUT

        self.triggerGPIO = triggerGPIO
        self.echoGPIO = echoGPIO
    }
    
    open func measureDistance(numberOfSamples: Int? = nil, providedTimeout: Int? = nil) throws -> Double {
        guard let echoGPIO = echoGPIO else {
            throw HCSR04Error.unavailableGPIO(detail: "Unable to read distance input due to missing echo input GPIO")
        }

        var beginningTimeOfEchoSignal: DispatchTime //The beginning of echo signal.
        var endTimeOfEchoSignal: DispatchTime //The end of echo signal.
        var echoSignalTime = Double.init() //Calculated echo signal time.
        var distance = Double.init() //Calculated distance.
        var enterTimeIntoWhile: DispatchTime //Used for timeout and error detection.
        let maximumEchoSignalTime = (maximumDistance/0.0000343) * 2 //Time of maximum echo signal for provided sensor range - used for error detection and default timeout.
        let defaultTimeout = maximumEchoSignalTime * 2  //Calculate timeout = (maximumEchoSignalTime)*(safety margin).
        let usedTimeout: Double //Finally used timeout - default or provided by user.
        
        if (providedTimeout == nil) {
            usedTimeout = defaultTimeout
        } else {
            usedTimeout = Double(providedTimeout! * 1000000) //convert miliseconds to nanoseconds, user provide timeout in miliseconds.
        }
        
        for _ in 0..<(numberOfSamples ?? 1) { //Default number of samples is 1, user can provide another number of samples by optional argument while calling method measureDistance
            
            //Start distance measure.
            try generateTriggerImpulse() //Generate trigger impuls 10 microseconds long.
            
            enterTimeIntoWhile = DispatchTime.now() //Save enter time into while loop for error detection.
            while (echoGPIO.value == 0) {
                if (calculateTimeInterval(from: enterTimeIntoWhile, to: DispatchTime.now()) > usedTimeout){
                    throw HCSR04Error.echoSignalError //Throw error
                }
            }
            beginningTimeOfEchoSignal = DispatchTime.now() //Save time of  beginning echo signal.
            
            enterTimeIntoWhile = DispatchTime.now() //Save enter time into while loop for error detection.
            while (echoGPIO.value == 1){ //Wait for end of echo signal.
                let timeInLoop = calculateTimeInterval(from: enterTimeIntoWhile, to: DispatchTime.now())
                if timeInLoop >= maximumEchoSignalTime {
                    throw HCSR04Error.measuredDistanceIsOutSensorRange //Throw error.
                } else if (providedTimeout != nil) && (timeInLoop > usedTimeout) {
                    throw HCSR04Error.userTimeout //Throw error - user timeout interrupt.
                }
            }
            endTimeOfEchoSignal = DispatchTime.now() //Save time of the end echo signal.
            
            echoSignalTime = calculateTimeInterval(from: beginningTimeOfEchoSignal, to: endTimeOfEchoSignal) //Calculate time of echo signal.
            distance = distance + (echoSignalTime * 0.0000343)/2 //Calculate distance: ((echo signal time in nanosecodns)*(speed of the sound cm per nanoseconds))/(distance divided by 2, echo signal round trip)).
            if numberOfSamples != nil {
                usleep(60000) //Wait 60ms before next sample measurement.
            }
        }
        distance = distance/Double(numberOfSamples ?? 1) //Calculate average distance.
        
        if distance <= maximumDistance {
            return distance
        } else {
            throw HCSR04Error.measuredDistanceIsOutSensorRange
        }
    }
    
    open func generateTriggerImpulse() throws {
        guard let triggerGPIO = triggerGPIO else {
            throw HCSR04Error.unavailableGPIO(detail: "Unable to trigger sonic impulse due to missing trigger output GPIO")
        }

        triggerGPIO.value = 1 //Set trigger pin High level.
        usleep(10)//Wait 10 microseconds.
        triggerGPIO.value = 0 //Set trigger pin Low level.
    }
    
    private func calculateTimeInterval(from startTime: DispatchTime, to endTime: DispatchTime) -> Double {
        return Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds)
    }
}

