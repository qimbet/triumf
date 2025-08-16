#debugging tools for the stepper motor
#run iterCoils() on a motor to iterate over all permutations of wire arrangements
#good tool for finding out how a motor is wired

#Jacob Mattie, August 7, 2025f


import itertools
import lgpio
from time import sleep


state = 0
h = lgpio.gpiochip_open(0)

coilPins = [("coilA1", 27), #list of tuples. Each entry is: (pinName, boardPinNumber)
            ("coilA2", 22), #the pinName string is for legibility only. Not used in code
            ("coilB1", 23), 
            ("coilB2", 24)]

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
		
	print(newCoilsList)
	for perm in itertools.permutations(newCoilsList):
		print(perm)
		goNum(numCycles, state, perm, delayTime)
