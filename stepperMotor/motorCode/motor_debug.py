#debugging tools for the stepper motor
#run iterCoils() on a motor to iterate over all permutations of wire arrangements
#good tool for finding out how a motor is wired

#Jacob Mattie, August 7, 2025f


import itertools
import lgpio
from time import sleep

delayBetweenSteps = 0.0025 #seconds
numSteps = 20000

coilPins = [27,23,22,24]

startState = 0
h = None

def stepOne(state, coils):
	nextState = (state+1) % 4
	for coil in coils: 
		lgpio.gpio_write(h, coil, 0)
	lgpio.gpio_write(h, coils[nextState], 1)
	return nextState

def goNum(numSteps, state, coils, delayTime):
	for el in range(numSteps):
		state = stepOne(state, coils)
		sleep(delayTime)

def iterCoils(numCycles, delayTime, coilsList):
	newCoilsList = []
	for coil in coilsList:
		newCoilsList.append(coil)	
	print(f"Current hardcoded coils arrangement: {newCoilsList}")

	for perm in itertools.permutations(newCoilsList):
		print("Cycling through coil arrangement: {perm}")
		goNum(numCycles, state, perm, delayTime)

def openHandle():
	global h
	h = lgpio.gpiochip_open(0) #should be closed at the end of the function

def closeHandle():
	global h
	lgpio.gpiochip.close(h)

if __name__ == "__main__":
	openHandle()

	x = input(f"""
	Enter any value to run a coil permutation test. 
	Leave blank to run a step series with hardcoded values:
		   Step Delay: {delayBetweenSteps*1000} milliseconds
		   Number of steps: {numSteps}
		   """)
	if x: 
		goNum(numSteps, startState, coilPins, delayBetweenSteps)	
	else: 
		iterCoils(numSteps, delayBetweenSteps, coilPins)

	closeHandle()