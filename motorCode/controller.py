"""
Raspberry pi as microcontroller for stepper motor
Created for the ASPIRE lab at Triumf


Written by Jacob Mattie, working under the guidance of Dr. Christopher Charles
July 28, 2025


--------------------------------------------------------------------------------

OVERVIEW:

The core of the function is in the ordered list coilPins.

The function step() increments the high-state output on the associated
pins in a way conducive to a unipolar stepper motor driver
i.e.
    pin1        ON      --- step 0
    pin1, pin2  ON      --- step 1
    pin2        ON      --- step 2
    pin2, pin3  ON      --- step 3
    ...                 
and so forth

The functions moveNumSteps and moveAngle dress up the step() function to 
make them more palatable, but ultimately do the same thing.

The order in which the motor windings are to be energized should be 
determined on a per-motor basis. This order can be set either in-code or 
through wiring.

The list coilPins is the program's ordering on outputs. 
Reorder, add/remove windings as needed.

"""

#requires installation of RPi.#GPIO module


#***********************************************************************
#
#                   VARIABLES & INITIALIZATION
#
#***********************************************************************

#import RPi.#GPIO as #GPIO
#for debugging on laptop, I've changeAll: GPIO --> #GPIO 

from time import sleep

debug = True

coilPins = [("coilA1", 0), #list of tuples. Each entry is: (pinName, boardPinNumber)
            ("coilA2", 1), #the pinName string is for legibility only. Not used in code
            ("coilB1", 2), 
            ("coilB2", 3)]

numCoils = len(coilPins)

for coil in coilPins:
    #GPIO.setup(coil[0], #GPIO.OUT) #assign coilPins as outputs
    pass #for debugging cases where GPIO gets commented out 

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

    def step(currentState, directionForward):
        #currentState is a list -- either one or two elements; describing the index values of which coilPins elements are energized

        if directionForward == True:
            if len(currentState) == 1:
                activatedPin = currentState[0]
                addPin = ((activatedPin+1) % numCoils) #reset to index 0 if at last element
                #GPIO.output(addPin, 1)

                currentState.append(addPin)

            elif len(currentState) == 2:
                laggingPin = currentState[0]
                #GPIO.output(laggingPin, 0)

                currentState.remove(laggingPin)

            else:
                return "ERROR"
            
        else: #reverse
            if len(currentState) == 1:
                activatedPin = currentState[0]
                addPin = ((activatedPin-1) % numCoils) #reset to index 0 if at last element
                #GPIO.output(addPin, 1)

                currentState.insert(0, addPin)

            elif len(currentState) == 2:
                laggingPin = currentState[1]
                #GPIO.output(laggingPin, 0)

                currentState.remove(laggingPin)

            else:
                return "ERROR"
        
        d(currentState)
        return currentState

    def moveNumSteps(steps, currentState, delay_between_steps__milliseconds=0):
        directionForward = True
        if steps < 0:
            steps = steps * (-1)
            directionForward = False

        state = currentState

        for i in range(steps):
            state = step(state, directionForward)
            sleep(delay_between_steps__milliseconds)

        return state

    def moveAngle(angle, currentState, anglePerStep=1.8, delay_between_steps__milliseconds=0):
        #anglePerStep is set based off typical stepper motor parameters
        #The ASPIRE motor setup uses an opaque gearbox -- anglePerStep is best found experimentally

        #feed a negative value into 'angle' to rotate counter-clockwise

        numStepsDecimal = angle/anglePerStep
        numStepsInteger = int(round(numStepsDecimal, 0))

        newState = moveNumSteps(numStepsInteger, currentState, delay_between_steps__milliseconds)

        return newState

#***********************************************************************
#
#                   MAIN LOOP
#
#***********************************************************************

if __name__ == '__main__':

    startingState = [0] #assuming element 0 of the coilPins list is energized during startup

    delay_between_steps__milliseconds = 0
    delayVal = milliSec(delay_between_steps__milliseconds)

    steps = 0


    currentState = startingState
    for pin in startingState:
        #GPIO.output(coilPins[pin], 1)
        pass #for debugging cases where GPIO gets commented out

    while True:
        while True:
            stepsStr = input("""
            How many steps should the motor move?
            
            The motor moves clockwise by default. 
            Enter a negative step number to rotate counterclockwise.
                
            >>  """)
            if stepsStr.isdigit():
                steps = int(round(float(stepsStr), 0))
                break
            else:
                print("That was not an integer.\n")
        
        currentState = moveNumSteps(steps, currentState, delayVal)