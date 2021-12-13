This is a experimental application for simulating evolution. This is work in progress.

## Setup
Install V Lang compiler :

```
git clone https://github.com/vlang/v
cd v
make
```

Symlink the executable

Unix Systems:

```
sudo ./v symlink
```

Windows:

```
.\v.exe symlink
```

## Running

Currently you need to change something in the V workspace for this project to run (V is in alpha and rendering in the gg (stands for graphics) module is bound to lowest hardware specs).

Change the const `_SGL_DEFAULT_MAX_VERTICES` in the file `thirdparty/sokol/util/sokol_gl.h`, that should do it, at least for now, if rendering gets more demanding in the future, this might change though...

```
#define _SGL_DEFAULT_MAX_VERTICES (1<<19)
```

```
v run simulator.v
```

## Controlling

- <kbd>Space</kbd> Pause
  
- <kbd>D</kbd> Enable debug rendering
  
- <kbd>R</kbd> Reset the simulation
  
- <kbd>G</kbd> Show Grid
  
- <kbd>T</kbd> Show current tick
  
- <kbd>Shift</kbd> + <kbd>T</kbd> Jump forward to some tick (from stdin)
  
- <kbd>-></kbd> Decrease time between ticks 100ms (speed up)
  
- <kbd>Shift</kbd> + <kbd>-></kbd> Decrease time between ticks 10ms (speed up)
  
- <kbd><-</kbd> Increase time between ticks 100ms (speed down)
  
- <kbd>Shift</kbd> + <kbd><-</kbd> Increase time between ticks 10ms (speed down)

- Pausing the game and left clicking on a creature prints out its genome data on the console
  
- Debug rendering currently shows creatures with specific genome properties, like `predator`, `defender`, `strong_defender`

## License

GNU General Public License v3.0 (see LICENSE file)