"""
Raspberry pi as microcontroller for stepper motor
Created for the ASPIRE lab at Triumf


Written by Jacob Mattie
July 28, 2025

j_mattie@live.ca
https://github.com/qimbet/triumf/tree/main/motorCode


--------------------------------------------------------------------------------

OVERVIEW:

The core of the function is in the ordered list coilPins.

The function halfStep() increments the high-state output on the associated
pins in a way conducive to a unipolar stepper motor driver
i.e.
    pin1        ON      --- step 0
    pin1, pin2  ON      --- step 1
    pin2        ON      --- step 2
    pin2, pin3  ON      --- step 3
    ...                 
and so forth

step() limits pin activation to one at a time

The functions moveNumSteps and moveAngle dress up the step() function to 
make them more palatable, but ultimately do the same thing.

The order in which the motor windings are to be energized should be 
determined on a per-motor basis. This order can be set either in-code 
(by re-ordering coilPins) or through wiring.

The list coilPins is the program's ordering on outputs. 
Reorder, add/remove windings as needed.

"""

#Prior to runtime, install the lgpio library:
    #pip install lgpio
    #sudo apt update
    #sudo apt install lgpio


#***********************************************************************
#
#                   VARIABLES & INITIALIZATION
#
#***********************************************************************

from time import sleep
import lgpio
import atexit
import signal
import sys


debug = False #prints process text if True; see d()
delayBetweenMotorSteps = 25 #milliseconds; slow down rotation speed if needed
anglePerMotorStep = 0.01 #roughly

coilPins = [27,23,22,24] #A1, B1, A2, B2


h = None #chip handle; later used for lgpio

startingState = [0] #assuming element 0 of the coilPins list is to be energized during startup
numCoils = len(coilPins)

#***********************************************************************
#
#                   FUNCTION DEFINITIONS
#
#***********************************************************************

if True:
    def d(val): #debug function
        if debug == True:
            print(val)

    def milliSec(s):
        return (s/1000)

    def initPins(coilPins):
        for pinNumber in coilPins:
            lgpio.gpio_claim_output(h, pinNumber, 0)  # Claim as output, initial value 0 (LOW)

    def halfStep(directionForward=True, currentState=[0]): #temporarily deprecated for simplicity: use step().
        #currentState is a list -- either one or two elements; describing the index values of which coilPins elements are energized

        if directionForward == True:
            if len(currentState) == 1:
                activatedPin = currentState[0]

                addPinIndex = ((activatedPin+1) % numCoils) #reset to index 0 if at last element
                addPin = coilPins[addPinIndex]
                lgpio.gpio_write(h, addPin, 1) 

                currentState.append(addPinIndex)

            elif len(currentState) == 2:
                laggingPinIndex = currentState[0]

                laggingPin = coilPins[laggingPinIndex]
                lgpio.gpio_write(h, laggingPin, 0) 

                currentState.remove(laggingPinIndex)

            else:
                return "ERROR"
            
        else: #reverse
            if len(currentState) == 1:
                activatedPin = currentState[0]

                addPinIndex = ((activatedPin-1) % numCoils) #reset to index 0 if at last element
                addPin = coilPins[addPinIndex]
                lgpio.gpio_write(h, addPin, 1) 

                currentState.insert(0, addPinIndex)

            elif len(currentState) == 2:
                laggingPinIndex = currentState[-1]
                laggingPin = coilPins[laggingPinIndex]
                lgpio.gpio_write(h, laggingPin, 0) 

                currentState.remove(laggingPinIndex)

            else:
                return "ERROR"
        
        d(currentState)
        return currentState

    def step(directionForward=True, currentState=[0]):
        #currentState is a list -- either one or two elements; describing the index values of which coilPins elements are energized

        if directionForward == True:
            activatedPin = currentState[0]
            addPinIndex = ((activatedPin+1) % numCoils) #reset to index 0 if at last element
            addPin = coilPins[addPinIndex]

            lgpio.gpio_write(h, activatedPin, 0)
            lgpio.gpio_write(h, addPin, 1) 

            currentState = [addPin]
            
        else: #reverse
            activatedPin = currentState[0]
            addPinIndex = ((activatedPin-1) % numCoils) #reset to index 0 if at last element
            addPin = coilPins[addPinIndex]

            lgpio.gpio_write(h, activatedPin, 0)
            lgpio.gpio_write(h, addPin, 1) 

            currentState = [addPin]
        
        d(currentState)
        return currentState

    def moveNumSteps(steps, currentState, delayBetweenMotorSteps_milliseconds=0):
        directionForward = True
        if steps < 0:
            steps = steps * (-1)
            directionForward = False

        state = currentState

        for i in range(steps):
            state = step(directionForward, state)
            sleep(delayBetweenMotorSteps_milliseconds)

        return state

    def moveAngle(angle, currentState, anglePerStep=0.01, delayBetweenMotorSteps_milliseconds=0):
        #anglePerStep default is set based off typical stepper motor parameters
        #The ASPIRE motor setup uses an opaque gearbox -- anglePerStep is best found experimentally

        #feed a negative value into 'angle' to rotate counter-clockwise

        numStepsDecimal = angle/anglePerStep
        numStepsInteger = int(round(numStepsDecimal, 0))

        newState = moveNumSteps(numStepsInteger, currentState, delayBetweenMotorSteps_milliseconds)

        return newState

#**********************************
#              Memory Handling
if True:
    def openHandle():
        global h
        h = lgpio.gpiochip_open(0)

    def cleanup():
        lgpio.gpiochip_close(h)

    def signalHandler(_sig, _frame): #arguments unused but required feed by signal.signal
        cleanup()
        sys.exit()

    atexit.register(cleanup) #call cleanup() on normal exit
    signal.signal(signal.SIGINT, signalHandler) #Ctrl-C
    signal.signal(signal.SIGTERM, signalHandler) #pkill, etc.
    signal.signal(signal.SIGHUP, signalHandler) #controller session disconnect

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

def main():
    global h, startingState
    openHandle()
    
    initPins(coilPins)

    delayVal = milliSec(delayBetweenMotorSteps)

    angle = 0
    currentState = startingState

    for pin in startingState:
        lgpio.gpio_write(h, coilPins[pin], 1)
        pass #pass: for debugging cases where pi.set_mode gets commented out 

    while True:
        while True:
            angleStr = input("""
            How many degrees should the motor rotate? 
            
            The motor moves clockwise by default. 
            Enter a negative step number to rotate counterclockwise.
                
            >>  """) #should update for angle -- more intuitive on a GUI. Calibration needed.

            try: 
                angle = float(angleStr)
                break
            except:
                print("That was not an integer.\n")
        
        currentState = moveAngle(angle, currentState, anglePerMotorStep, delayVal) #moveAngle(angle, currentState, anglePerMotorStep, delayVal)
        print(f"Motor moved {angle} degrees.\n ")

#**********************************
#              Direct Calls

if __name__ == '__main__':
    main()

