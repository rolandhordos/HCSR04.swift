import SwiftyGPIO
import Foundation
import Dispatch

/// Create an instance representing the HC-SR04 hardware module
///
/// Avoiding *pin* terminology favoring GPIO## as that's what the SwiftyGPIO `.P##` enumeration cases are (vs board pin #).
/// [Raspberry Pi Pinout](https://www.raspberrypi.com/documentation/computers/os.html#gpio-pinout)
///
/// Default maximum distance comes from [the datasheet](https://cdn.sparkfun.com/datasheets/Sensors/Proximity/HCSR04.pdf)
///
open class HCSR04 {

    public enum Error: Swift.Error {
        case echoSignalError(String? = nil)
        case measuredDistanceIsOutSensorRange
        case userTimeout
        case unavailableGPIO(String? = nil)
    }

    public typealias CentiMeters = Double
    public typealias MetersPerSecond = Double
    
    public var triggerGPIO    : GPIO?                           // ultrasonic emitter sends first
    public var echoGPIO       : GPIO?                           // ultrasonic receiver then receives returned sound waves
    public var maximumDistance: CentiMeters     = 400           // default upper range from datasheet
    public var speedOfSound   : MetersPerSecond = 343           // from wikipedia as speed of sound in air, note datasheet says 340

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
            throw Error.unavailableGPIO("Echo GPIO number \(echo) not available, check power and wiring")
        }
        echoGPIO.direction = .IN
        
        guard let triggerGPIO = gpios[trigger] else {
            throw Error.unavailableGPIO("Trigger GPIO number \(echo) not available, check power and wiring")
        }
        triggerGPIO.direction = .OUT

        self.triggerGPIO = triggerGPIO
        self.echoGPIO = echoGPIO
    }
    
    
    /// Return measured average distance
    ///
    /// Timeout will be calculated by default based on maximum distance.  Caution if setting a large timeout as this function is very expensive,
    /// spinning in a while loop during pulse detection.  Setting a timeout includes the time to take *all* samples
    ///
    /// Times are in nanoseconds unless specified, note that TimeInterval is in seconds
    ///
    open func measureDistance(numberOfSamples: Int = 1, timeout: DispatchTimeInterval? = nil) throws -> CentiMeters {
        guard let echoGPIO = echoGPIO else {
            throw Error.unavailableGPIO("Unable to read distance input due to missing echo input GPIO")
        }

        let maximumTravel: CentiMeters = maximumDistance * 2                            // there and back
        let maximumTravelTime: TimeInterval = maximumTravel / (speedOfSound * 100)      // 100 cm in a meter
        let maximumTravelTimeAllSamples: TimeInterval = maximumTravelTime * Double(numberOfSamples)

        // careful converting so we don't truncate the double
        let maximumEchoSignalDuration: DispatchTimeInterval = .milliseconds(Int(maximumTravelTime * 1000.0))

        // use provided timeout or use theoretical maximum padded with a feels-good margin
        let paddingFactor = 1.5
        let timeoutDuration: DispatchTimeInterval = timeout ?? .milliseconds(Int(maximumTravelTimeAllSamples * 1000.0 * paddingFactor))

        let timeoutAt = DispatchTime.now() + timeoutDuration                            // timeout as a fixed point in time
        var totalDistance: CentiMeters = 0                                              // tally over all samples
        for sample in 1..<numberOfSamples + 1 {
            
            //Start distance measure.
            try generateTriggerImpulse() //Generate trigger impuls 10 microseconds long.
            
            // Pulse detection starting with low signal on leading edge
            while echoGPIO.value == 0 {
                if DispatchTime.now() > timeoutAt {
                    throw Error.echoSignalError("Timeout occurred during front edge of pulse detection")
                }
            }

            let beginningTimeOfEchoSignal = DispatchTime.now() //Save time of  beginning echo signal.

            // Detect the rise in pulse and measure it's duration
            let maximumEchoAt = DispatchTime.now() + maximumEchoSignalDuration
            while echoGPIO.value == 1 { //Wait for end of echo signal.
                let now = DispatchTime.now()
                if now > maximumEchoAt {
                    throw Error.measuredDistanceIsOutSensorRange //Throw error.
                } else if (timeout != nil) && (now > timeoutAt) {
                    throw Error.userTimeout //Throw error - user timeout interrupt.
                }
            }
            let endTimeOfEchoSignal = DispatchTime.now()

            let echoSignalTime = endTimeOfEchoSignal.uptimeNanoseconds - beginningTimeOfEchoSignal.uptimeNanoseconds
            totalDistance = totalDistance + (Double(echoSignalTime) * 0.0000343)/2 //Calculate distance: ((echo signal time in nanosecodns)*(speed of the sound cm per nanoseconds))/(distance divided by 2, echo signal round trip)).
            if sample < numberOfSamples {
                usleep(60000) //Wait 60ms before next sample measurement.
            }
        }
        
        let averageDistance = totalDistance / Double(numberOfSamples)
        guard averageDistance <= maximumDistance else {
            throw Error.measuredDistanceIsOutSensorRange
        }
        return averageDistance
    }
    
    open func generateTriggerImpulse() throws {
        guard let triggerGPIO = triggerGPIO else {
            throw Error.unavailableGPIO("Unable to trigger sonic impulse due to missing trigger output GPIO")
        }

        triggerGPIO.value = 1 //Set trigger pin High level.
        usleep(10)//Wait 10 microseconds.
        triggerGPIO.value = 0 //Set trigger pin Low level.
    }
}

