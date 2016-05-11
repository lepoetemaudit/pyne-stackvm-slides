% Implementing a Stack-based VM and Compiler in Python
% Dave Jeffrey // @unpoetemaudit // May 11th, 2016
% With thanks to Paweł Widera whose template I ~~stole~~ based this off

## A brief introduction

![to implementing virtual machines and compilers with Python](https://i.ytimg.com/vi/lt-udg9zQSE/hqdefault.jpg)

## Follow online

http://tinyurl.com/jty6cck

## Why implement a virtual machine?

* Emulators (systems, games consoles)
* Sandboxed environment
* Language runtimes (e.g. Python, JVM, .NET)
* Learning about processor design
* Scripting for your application
* The sheer hell of it

## A very brief overview of the CPU

- Reads "instructions", which are simple commands
- Handles basic arithmetic / bit manipulations
- Low-level input/output
- Memory access
- Logic and control-flow (i.e. loops, jumps, conditionals)

## CPU instructions

Instructions are just numbers (usually expressed in hex), e.g.

"B0h 10h"

On x86 compatible processors, this sets ('moves') the low part of the A register to the value 0x10.

Generally, we work with an assembler, which uses names instead of numbers but mostly maps one to one, e.g.

~~~{.nasm}
mov bx, 000Fh   ; Page 0, colour attribute 15 (white) for the int 10 calls below
mov cx, 1       ; We will want to write 1 character
xor dx, dx      ; Start at top left corner
mov ds, dx      ; Ensure ds = 0 (to let us load the message)
cld             ; Ensure direction flag is cleared (for LODSB)
~~~

# Register vs stack CPU

## Register based

- Register based CPUs have many little 'boxes' for working variables called registers, often
numbered or given letter names
- <br>
- Instructions tend to take 'operands' (arguments) in order to specify the target registers, e.g. `mov bx, 000Fh` - "move" takes two operands - the target register, and the value to set


## Stack based

- Stack based CPUs have very few registers (often just an instruction pointer)
- <br>
- Instead, stack based CPUs use a 'stack', an abstract sort of container into which you can 'push'
values and 'pop' out values

## Stack based (continued)
- Most instructions take zero operands, so they are very easy to implement - for example, `ADD` takes no operands, pops two values off the stack, adds them together, and then pushes them back onto the stack.

Example:

~~~{.nasm}
PUSH 10
PUSH 20
ADD ; Result is "30"
~~~

## Stack based (continued)

If we fiddle a little bit with the assembler, we can get something that looks like this:


`10 20 +`


This looks like an RPN calculator! And it is.

Making a toy language for a stack-based VM should be as simple as sugaring up its assembler representation...

## Real vs virtual machines

- Hardware machines tend to be register based
- Virtual machines are very often stack based (Lua, Python, JVM)

# A brief rant about 'bare-metal'

# Let's define our machine

## Our machine definition

~~~{.python}
from collections import namedtuple, deque

MAIN_STACK_SIZE = 0x800
CALL_STACK_SIZE = 0x400

MAX_INT = 0x799F
MIN_INT = -0x8000

# Store the state of our machine
Machine = namedtuple(
    'Machine',
    ['main_stack',
     'call_stack',
     'instruction_pointer',
     'code'])


# Definition of instructions
Instruction = namedtuple(
    'Instruction',
    ['opcode',
     'name',
     'execute'])

def w(val):
    while val > MAX_INT:
        val -= 0x10000

    while val < MIN_INT:
        val += 0x10000

    return val     
~~~

## If it's easier...

Go and clone https://github.com/pyne-stackvm and look at `machine.py`

## Some helpers

~~~{.python}
def push_stack(machine, val):
    if len(machine.main_stack) >= MAIN_STACK_SIZE:
        raise MachineError("Stack overflow: %x", machine)
    machine.main_stack.append(w(val))

    return machine


def pop_stack(machine):
    if len(machine.main_stack) == 0:
        raise MachineError("Stack underflow: %x", machine)

    return machine.main_stack.pop()


class MachineError(BaseException):
    def __init__(self, message, machine):
        super(MachineError, self).__init__(self, message)
        self.machine = machine


def make_machine(code=None):
    return Machine(
        main_stack=deque(), call_stack=deque(),
        instruction_pointer=0, code=code or [])        
~~~

## Define our opcodes

~~~{.python}
# Stack operations
PUSH = 0x01
POP = 0x02
COPY = 0x03
SWAP = 0x04

# Arithmetic operations
ADD = 0x20
SUB = 0x21

# Control operations
JZ = 0x30
JG = 0x31
JL = 0x32
CALL = 0x33
RET = 0x34

# IO
PUTCH = 0x50
PUTDEC = 0x51
PUTHEX = 0x52
PUTS = 0x53

# Machine operations
HALT = 0x00
~~~

## Now let's define some instructions

~~~{.python}
# 0x01 - PUSH
def _op_push(machine):
    # Get the next code word as the value to push
    word, machine = next_instruction(machine)
    return push_stack(machine, word)

# 0x03 - COPY
def _op_copy(machine):
    word = pop_stack(machine)
    return push_stack(push_stack(machine, word), word)


# 0x20 - ADD
def _op_add(machine):
    return push_stack(
        machine,
        pop_stack(machine) + pop_stack(machine))

# 0x21 - SUB
def _op_sub(machine):
    op2, op1 = (pop_stack(machine) for _ in range(2))
    return push_stack(machine, op1 - op2)
~~~

## Control...

~~~{.python}
# 0x40 - JZ (Jump if zero)
def _op_jmp_zero(machine):
    new_ip, result = (pop_stack(machine) for _ in range(2))
    if result == 0:
        return Machine(
            machine.main_stack, machine.call_stack, new_ip, machine.code)
    return machine

# 0x41 - JG (Jump if greater)
def _op_jmp_greater(machine):
    new_ip, result = (pop_stack(machine) for _ in range(2))
    if result > 0:
        return Machine(
            machine.main_stack, machine.call_stack, new_ip, machine.code)
    return machine

# 0x42 - JG (Jump if greater)
def _op_jmp_less(machine):
    new_ip, result = (pop_stack(machine) for _ in range(2))
    if result < 0:
        return Machine(
            machine.main_stack, machine.call_stack, new_ip, machine.code)
    return machine
~~~

## And some cheat instructions for doing output

On a normal machine, you'd have to write to video memory, OUT to a port or
some such mechanism, but this is more convenient

~~~{.python}
# 0x50 - PUTCH
def _op_putch(machine):
    val = pop_stack(machine)
    sys.stdout.write(chr(val))
    return machine

# 0x51 - PUTDEC
def _op_putdec(machine):
    val = pop_stack(machine)
    print(val)
    return machine
~~~

Let's make a helper so we can debug instructions:

```python
def describe_instruction(instruction):
    return "0x%.2x -> %s" % instruction[0:2]
```

## Dispatch table

This routes opcodes to the right function


```python
dispatch_table = {
    # Stack operations
    PUSH: Instruction(PUSH, "PUSH", _op_push),
    COPY: Instruction(COPY, "COPY", _op_copy),

    # Arithmetic operations
    ADD: Instruction(ADD, "ADD", _op_add),
    SUB: Instruction(SUB, "SUB", _op_sub),

    # Control operations
    JZ: Instruction(JZ, "JZ", _op_jmp_zero),
    JG: Instruction(JG, "JG", _op_jmp_greater),
    JL: Instruction(JL, "JL", _op_jmp_less),

    # IO operations
    PUTCH: Instruction(PUTCH, "PUTCH", _op_putch),
    PUTDEC: Instruction(PUTDEC, "PUTDEC", _op_putdec)
}
```

# Let's make the machine itself

## Each cycle we want to:

- Fetch the instruction from the code array pointed to by the instruction pointer
- <br>
- Execute the instruction, which updates the state in our virtual machine

## It's really simple:

```python
def next_instruction(machine):
    main_stack, call_stack, ip, code = machine

    # Bounds check on ip
    if ip >= len(code) or ip < 0:
        raise MachineError(
            "ip out of code range: ip=%d, code size=%d" % (ip, len(code)),
            machine)

    # Fetch next instruction opcode (or argument for certain opcodes)
    opcode = code[ip]

    # Return the machine with the instruction pointer incremented
    return opcode, Machine(main_stack, call_stack, ip+1, code)
```
## And step the machine instruction by instruction

```python
def step_machine(machine, debug=True):
    opcode, machine = next_instruction(machine)

    # Match and execute on instruction with our dispatch table
    instruction = dispatch_table.get(opcode)
    if not instruction:
        raise MachineError("Got bad opcode: %x" % opcode, machine)
    if debug:
        print("++ Exec ip=%d [%s]" % (
            machine.instruction_pointer,
            describe_instruction(instruction)))

    return instruction.execute(machine)
```

## Let's make that loop
```python
def run_machine(machine, debug=True):
    """
    Run the machine until it errors or we hit a HALT instruction
    """

    while True:
        # Bounds check
        if len(machine.code) <= machine.instruction_pointer:
             raise MachineError(
                "ip out of code range: ip=%d, code size=%d" % (
                    machine.instruction_pointer,
                    len(machine.code)),
                machine)

        # Stop on HALT instruction
        if machine.code[machine.instruction_pointer] == HALT:
            if debug:
                print("++ HALT")
            return machine
        else:
            machine = step_machine(machine, debug)
```            

## And let's make a little shortcut

This executes a series of instructions in `code`, returning
the top-most item left in the stack

```python
def run_code_for_result(code, debug=False):
    """
    A shortcut for running some code and returning just the result
    """
    return run_machine(make_machine(code), debug).main_stack.pop()
```

# Let's try it out...

## Some test programs

```python
# Note how with the opcode names these programs look
# almost like assembler code, even though they are
# just lists of numbers

PUSH_AND_HALT = [
    PUSH, 0x66, # PUSH 66
    HALT]       # HALT

run_code_for_result(PUSH_AND_HALT)
# Result -> 66

ADD_TWO_AND_THREE = [
    PUSH, 0x2, # PUSH 2
    PUSH, 0x3, # PUSH 3
    ADD,       # ADD
    HALT]      # HALT

run_code_for_result(ADD_TWO_AND_THREE)
# Result -> 5

```

<br>
Some more example programs: [https://github.com/lepoetemaudit/pyne-stackvm/blob/master/programs.py](https://github.com/lepoetemaudit/pyne-stackvm/blob/master/programs.py)

# Yay! But not so thrilling...

## Difficulties

- It's very unwieldy writing code like this
- <br>
- Jumps (i.e. gotos) in particular are a nightmare as we need to use absolute addresses - which change as soon as we move our code around!

# Let's make a compiler

## This code is pretty dull...

Go clone https://github.com/lepoetemaudit/pyne-stackvm or follow online there

Seriously, tokenizers are very dull

## Basics of a compiler (more or less an assembler in this case)

- Take 'tokens', i.e. numbers, instructions, labels etc., and turn them into
  a series of numbers, i.e. our virtual machine's bytecode.
- <br>  
- Understands what is syntactically possible in a language and (hopefully)
  throws meaningful errors
- <br>
- We going to try and keep as close to our stack machine as possible

## Let's define our tokens

```python
# "This is a string"
STRING = "S"

# 0x10, 1000
NUMBER = "N"

# +, -, HALT, JZ etc.,
INSTRUCTION = "I"

# A 'label' is a shorthand for a memory address, e.g. :loop_start
LABEL = "L"

# The label ref refers to a defined label, e.g. @loop_start
LABEL_REF = "R"`
```

## Feed tokens into a compile loop

```python
def compile_string(code):
    code_points = []
    symbol_table = []
    for token, typ in get_tokens(code + "\n"):
        if typ == NUMBER:
            code_points += [opcodes.PUSH, machine.w(token)]
        elif typ == STRING:
            # We reverse it so it pops out in the right order
            for c in reversed(token):
                code_points += [opcodes.PUSH, ord(c)]
        elif typ == INSTRUCTION:
            code_points.append(token)

        elif typ == LABEL:
            symbol_table.append((len(code_points), token))

        elif typ == LABEL_REF:
            code_points += [opcodes.PUSH, token]

    code_points.append(opcodes.HALT)

    # Do a final pass and replace any refs with their code positions
    output = []
    for c in code_points:
        if isinstance(c, str):
            try:
                label = next(l for l in symbol_table if c == l[1])
                output.append(label[0])
            except StopIteration:
                raise CompilerError("Unknown symbol: %s" % token)
        else:
            output.append(c)

    return output
```

## Let's compile and run!

```python
10

:LOOP
1 -

COPY PUTDEC

COPY 0 = @LOOP JG
"Y" PUTCH
0
```

<br>
```bash
python compiler.py examples/countdown.dj bin/countdown.djo

python machine.py bin/countdown.djo

# Output:
# 9
# 8
# 7
# 6
# 5
# 4
# 3
# 2
# 1
# 0
# Y
# Result -> 0
```

# Where next?

## This project

- Memory / variable access
- <br>
- Implement call/return for functions
- <br>
- Add other arithmetic operators (*, /, % etc)
- <br>
- Make a REPL / interpreter

## Other projects

- Make a lisp [https://github.com/kanaka/mal](https://github.com/kanaka/mal)
- <br>
- SICP [http://ocw.mit.edu/courses/electrical-engineering-and-computer-science/6-001-structure-and-interpretation-of-computer-programs-spring-2005/video-lectures/](http://ocw.mit.edu/courses/electrical-engineering-and-computer-science/6-001-structure-and-interpretation-of-computer-programs-spring-2005/video-lectures/)

## Final word

If you really want to play around with compilers, I'd really recommend
picking up a bit of OCaml, F#, Haskell, or even Swift and Rust (basically,
any language with algebraic "sum" types, decent static typing and pattern
matching)

I used `mypy` [http://mypy-lang.org/](http://mypy-lang.org/) when preparing this talk, which also
really helped.

Lisps, although dynamic, are also excellent due to their syntactic
flexibility. Plus, "code as data" means you may even be able to implement
your toy language within LISP itself (or why not make a LISP?)

## Thank you

- Dave Jeffrey
- Lead developer at SoPost
- @unpoetemaudit
