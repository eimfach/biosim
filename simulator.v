/*
author: Robin T. Gruenke
 * date:   13.12.2021
 * licencse: GNU General Public License v3.0
*/
module main

import gg
import gx
import rand
import rand.util as rutil
import time
import os

const (
	win_width           = 800
	win_height          = 800
	lower_color_space   = 0x3f
	upper_color_space   = 0xcf
	max_temp 						= 32
	repro_age           = 40
	repro_cost					= 15
	sharing_success_chance = 1
	init_creature_count = 1000
)

struct App {
mut:
	gg             &gg.Context
	grid           [][]GridTile
	creature_count int
	ticks          i64 = time.ticks()
	accumulator    i64
	tick_count     i64
	update_time    int = 100
	paused         bool
	debug          bool
	show_grid      bool
	debug_grid     [][]DebugGridTile = [][]DebugGridTile{}
	seed           []u32
	mode           Mode
}

enum UpdateThreshold {
	slower
	faster
	even_slower
	even_faster
}

fn (mut app App) refresh_update_threshold(t UpdateThreshold) {
	match t {
		.slower { app.update_time += 10 }
		.faster { app.update_time -= 10 }
		.even_slower { app.update_time += 100 }
		.even_faster { app.update_time -= 100 }
	}
	if app.update_time < 0 {
		app.update_time = 0
	}
}

fn (mut app App) reset() {
	app.grid = [][]GridTile{}
	app.ticks = time.ticks()
	app.accumulator = 0
	app.debug_grid = [][]DebugGridTile{}
	app.tick_count = 0
	init(mut app)
}

struct Pause {}

struct Jump {
	to_tick i64
}

struct Play {}

struct WaitForInput {
	next_mode Mode
}

type Mode = Jump | Pause | Play | WaitForInput

struct Coordinate {
	x f32
	y f32
}

struct DebugGridTile {
	Coordinate
	color gx.Color
}

struct GridTile {
	Coordinate
mut:
	occupation Occupation
}

struct SomethingElse {}

type Inhabitant = Creature | SomethingElse

struct Occupied {
mut:
	inhabitant Inhabitant
}

struct Empty {}

struct BedRock {}

type Occupation = BedRock | Empty | Occupied

struct Creature {
mut:
	genome        Genome
	age           byte
	color         gx.Color
	life          Life
	reproduced    bool
	temp          byte
	received_temp byte
	generation    int
	debug         bool
}

fn (c &Creature) is_debug() bool {
	return c.debug
}

fn (mut c Creature) use_movement_energy() {
	mut nt := c.temp - 1
	if c.genome.immune_system.has(.defender) {
		nt -= 5
	}

	if c.genome.immune_system.all(.defender | .strong_defender) {
		nt -= 15
	}

	if c.genome.social.has(.predator) {
		nt -= 5
	}

	if nt == 0 || c.temp < nt {
		nt = 0
		c.life = .dead
	}

	c.temp = nt

	if c.received_temp > 0 {
		if c.received_temp <= 10 {
			c.received_temp -= 1
		}
		if c.received_temp >= 25 {
			c.received_temp -= 5
		}
	}
}

fn (mut c Creature) loose_neighbour_temp() {
	c.received_temp = 0
}

fn (mut c Creature) exchange_temp() {
	if c.temp < 30 {
		c.temp += 2
	}
	if c.received_temp > 180 {
		c.received_temp += 0
	} else if c.received_temp > 120 {
		c.received_temp += 1
	} else if c.received_temp > 25 {
		c.received_temp += 10
	} else {
		c.received_temp += 50
	}
}

fn (mut c Creature) flag_as_debug() {
	dg := debug_genome()
	c.genome = dg
	c.color = color_space(dg)
	c.life = .alive
	c.temp = 255
	c.debug = true
}

fn (mut c Creature) ages(a byte) {
	na := c.age + a

	if na == 255 || na < c.age {
		c.age = 255
	} else {
		c.age = na
	}
}

fn (mut c Creature) add_temp(t byte) {
	nt := c.temp + t
	if nt >= max_temp {
		c.temp = max_temp
	} else {
		c.temp = nt
	}
}

fn (mut c Creature) remove_temp(t byte) {
	nt := c.temp - t
	if nt <= 0 || nt > c.temp {
		c.temp = 0
		c.life = .dead
	} else {
		c.temp = nt
	}
}

enum Life {
	alive
	dead
}

struct Genome {
mut:
	movement         MovementGene
	direction_sensor DirectionSensorGene
	metabolism       MetabolismGene
	social           SocialGene
	ageing           AgeingGene
	immune_system    ImmuneSystemGene
	mutation_rate    MutationRateGene
}

[flag]
enum MutationRateGene {
	slower
	slow
	normal
	fast
	faster
	insane
}

[flag]
enum ImmuneSystemGene {
	normal
	defender
	strong_defender
}

[flag]
enum AgeingGene {
	faster
	fast
	normal
	slow
	slower
}

[flag]
enum MovementGene {
	able
	unable
}

[flag]
enum MetabolismGene {
	slow
	normal
	fast
}

[flag]
enum DirectionSensorGene {
	north
	east
	south
	west
	center
}

fn (dsg DirectionSensorGene) sum() byte {
	// print(byte(dsg))
	// print('|')
	return byte(dsg)
}

[flag]
enum SocialGene {
	normal
	sharing
	predator
}

enum Direction {
	north
	east
	south
	west
}

fn main() {
	mut app := &App{
		gg: 0
		mode: Play{}
	}
	app.gg = gg.new_context(
		bg_color: gx.white
		width: win_width
		height: win_height
		borderless_window: true
		resizable: false
		create_window: true
		window_title: 'Rectangles'
		frame_fn: frame
		user_data: app
		init_fn: init
		keydown_fn: on_keydown
		click_fn: on_click
	)

	app.gg.run()
}

[live]
fn init(mut app App) {
	if app.seed.len == 2 {
		println('seeding fixed: $app.seed')
		rand.seed(app.seed)
	}

	mut creatures := init_creatures(init_creature_count)
	creatures[100].flag_as_debug()
	grid := init_grid(mut creatures)

	app.grid = grid
}

fn init_creatures(count int) []Creature {
	mut creatures := []Creature{len: count, cap: count}

	for mut c in creatures {
		c = init_creature(genome: rand_genome())
	}

	return creatures
}

[params]
struct CreatureConfig {
	genome Genome = rand_genome()
}

fn init_creature(cfg CreatureConfig) Creature {
	color := color_space(cfg.genome)
	life := match rand.int_in_range(0, 64) {
		0 { Life.dead }
		else { Life.alive }
	}
	temp := if life == .dead { 0 } else { 32 }
	c := Creature{
		genome: cfg.genome
		color: color
		life: life
		temp: byte(temp)
	}
	return c
}

fn init_grid(mut creatures []Creature) [][]GridTile {
	mut grid := [][]GridTile{len: 80, cap: 80, init: []GridTile{len: 80, cap: 80}}

	for i, mut row in grid {
		for j, mut tile in row {
			tile = GridTile{
				x: j * 10
				y: i * 10
				occupation: Empty{}
			}
			if creatures.len > 0 && rand.int_in_range(0, 4) == 1 {
				c := creatures.pop()
				tile.occupation = Occupied{
					inhabitant: c
				}
			}
		}
	}

	return grid
}

fn frame(mut app App) {
	match app.mode {
		Pause {}
		WaitForInput {
			inp := os.input('Input tick to jump to (current: $app.tick_count):')
			mode := app.mode as WaitForInput

			match mode.next_mode {
				Pause {
					app.mode = mode.next_mode
				}
				WaitForInput {
					app.mode = mode.next_mode
				}
				Jump {
					to_tick := inp.i64()
					println('Jumping to tick: $to_tick ... this might take some time ...')
					app.mode = Jump{
						to_tick: to_tick
					}
				}
				Play {
					app.mode = mode.next_mode
				}
			}
		}
		Jump {
			mode := app.mode as Jump
			if mode.to_tick == app.tick_count {
				println('Jumped to tick $mode.to_tick, press space to continue ...')
				app.mode = Pause{}
				app.gg.begin()
				app.draw()
				app.gg.end()
			} else {
				run_tick(mut app)
			}
		}
		Play {
			run_tick(mut app)
			app.gg.begin()
			app.draw()
			app.gg.end()
		}
	}
}

fn run_tick(mut app App) {
	now := time.ticks()

	if app.accumulator >= app.update_time {
		for i, mut row in app.grid {
			for j, mut tile in row {
				creature_moves(mut app, mut row, mut tile, i, j)
				creature_reproduces(mut app, mut row, mut tile, i, j)
				creature_hunts(mut app, mut row, mut tile, i, j)
				creature_exchanges_temp(mut app, mut row, mut tile, i, j)
				// creatures eat, gain energy and temp
				creature_dies_of_age(mut tile)
				// creatures die of starvation
				// creatures die of heat death
				// creatures die of cold death
				// creatures die of disease
				creature_ages(mut tile)
				if app.tick_count % 50 == 0 {
					creature_decays(mut tile)
				}
			}
		}

		app.accumulator = 0
		app.tick_count += 1
	}

	app.accumulator += now - app.ticks
	app.ticks = now
}

[live]
fn (app &App) draw() {
	for row in app.grid {
		for tile in row {
			if app.show_grid {
				draw_grid(app, tile)
			}

			match tile.occupation {
				Empty {}
				BedRock {}
				Occupied {
					inhabitant := tile.occupation.inhabitant
					match inhabitant {
						Creature {
							if app.debug {
								// if inhabitant.is_debug() {
								// draw_debug_movement_tracing(app, tile, color_space(inhabitant.genome))
								// draw_debug_mark_creature(app, tile)
								// }
								if inhabitant.genome.movement.has(.able) {
									draw_debug_mark_creature(app, tile, gx.rgba(0x60,
										0xa0, 0x80, 0xff))
								}
							}

							draw_creature(app, tile, inhabitant)
						}
						SomethingElse {}
					}
				}
			}
		}
	}
}

fn draw_creature(app &App, tile &GridTile, c Creature) {
	color := c.color
	size := match_creature_draw_size(c)

	match c.life {
		.alive {
			app.gg.draw_circle_with_segments(tile.x + 5, tile.y + 5, size, 30, color)
		}
		.dead {
			app.gg.draw_circle_line(tile.x + 5, tile.y + 5, 3, 15, color)
		}
	}
}

fn match_creature_draw_size(c Creature) f32 {
	size := match true {
		c.age < 5 {1.5}
		c.age < 20 {2.0}
		else {2.5}
	}
	return f32(size)
}

fn draw_debug_mark_creature(app &App, tile GridTile, color gx.Color) {
	app.gg.draw_circle_line(tile.x + 5, tile.y + 5, 5, 15, color)
}

fn draw_debug_movement_tracing(app &App, tile GridTile, color gx.Color) {
	for tile_pair in app.debug_grid {
		app.gg.draw_line(tile_pair[0].x + 5, tile_pair[0].y + 5, tile_pair[1].x + 5,
			tile_pair[1].y + 5, color)
	}
}

fn draw_grid(app &App, tile GridTile) {
	app.gg.draw_empty_rect(tile.x, tile.y, 10, 10, gx.rgba(0, 0, 0, 10))
}

fn on_click(x f32, y f32, btn gg.MouseButton, mut app App) {
	match app.mode {
		Pause {
			if btn == .left {
				ix := int(x)
				iy := int(y)
				for row in app.grid {
					for tile in row {
						if ix >= tile.x && ix <= tile.x + 10 && iy >= tile.y && iy <= tile.y + 10 {
							match tile.occupation {
								Occupied {
									match tile.occupation.inhabitant {
										Creature {
											dump(tile.occupation.inhabitant)
										}
										SomethingElse {}
									}
								}
								Empty {}
								BedRock {}
							}
						}
					}
				}
			}
		}
		else {}
	}
}

fn on_keydown(code gg.KeyCode, mod gg.Modifier, mut app App) {
	match app.mode {
		Play {
			match code {
				.space {
					app.mode = Pause{}
				}
				.d {
					app.debug = !app.debug
				}
				.r {
					app.reset()
				}
				.g {
					app.show_grid = !app.show_grid
				}
				.t {
					if mod == .shift {
						app.mode = WaitForInput{
							next_mode: Jump{}
						}
					} else {
						println('Current tick: $app.tick_count')
					}
				}
				.right {
					if mod == .shift {
						app.refresh_update_threshold(.faster)
					} else {
						app.refresh_update_threshold(.even_faster)
					}
				}
				.left {
					if mod == .shift {
						app.refresh_update_threshold(.slower)
					} else {
						app.refresh_update_threshold(.even_slower)
					}
				}
				else {}
			}
		}
		Pause {
			match code {
				.space { app.mode = Play{} }
				else {}
			}
		}
		Jump {}
		WaitForInput {}
	}
}

fn creature_ages(mut tile GridTile) {
	match tile.occupation {
		Occupied {
			occupation := tile.occupation as Occupied
			inhabitant := occupation.inhabitant
			match inhabitant {
				Creature {
					mut c := inhabitant as Creature

					if c.life == .dead {
						return
					}
					match c.genome.ageing {
						.faster {
							c.ages(0xa)
						}
						.fast {
							c.ages(0x8)
						}
						.normal {
							c.ages(0x5)
						}
						.slow {
							c.ages(0x2)
						}
						.slower {
							c.ages(0x1)
						}
					}
					tile.occupation = Occupied{c}
				}
				SomethingElse {}
			}
		}
		else {}
	}
}

fn creature_decays(mut tile GridTile) {
	match tile.occupation {
		Occupied {
			occupation := tile.occupation as Occupied
			inhabitant := occupation.inhabitant
			match inhabitant {
				Creature {
					c := inhabitant as Creature
					if c.life == .dead {
						tile.occupation = Empty{}
					}
				}
				else {}
			}
		}
		else {}
	}
}

fn creature_dies_of_age(mut tile GridTile) {
	match tile.occupation {
		Occupied {
			occupation := tile.occupation as Occupied
			inhabitant := occupation.inhabitant
			match inhabitant {
				Creature {
					mut c := inhabitant as Creature
					if c.life == .dead {
						return
					}

					if c.age > 100 && c.age < 200 {
						match rand.int_in_range(0, 1000) {
							0 {
								c.life = .dead
								tile.occupation = Occupied{c}
							}
							else {}
						}
					} else if c.age > 200 && c.age < 255 {
						match rand.int_in_range(0, 140) {
							0 {
								c.life = .dead
								tile.occupation = Occupied{c}
							}
							else {}
						}
					} else if c.age == 255 {
						match rand.int_in_range(0, 10) {
							0 {
								c.life = .dead
								tile.occupation = Occupied{c}
							}
							else {}
						}
					} else {
					}
				}
				SomethingElse {}
			}
		}
		else {}
	}
}

fn creature_exchanges_temp(mut app App, mut row []GridTile, mut tile GridTile, i int, j int) {
	match tile.occupation {
		Occupied {
			occupation := tile.occupation as Occupied
			inhabitant := occupation.inhabitant
			match inhabitant {
				Creature {
					mut c := inhabitant as Creature
					mut neighbour_count := 0

					sharing_xor_predator := (SocialGene.sharing | SocialGene.predator) & c.genome.social

					if !c.genome.social.has(sharing_xor_predator) {
						return
					}

					for dir in [Direction.north, Direction.east, Direction.south, Direction.west] {
						row_index, tile_index := match_direction(dir, i, j)
						n_row := app.grid[row_index] or { continue }
						n_tile := n_row[tile_index] or { continue }

						match n_tile.occupation {
							Occupied {
								o := n_tile.occupation as Occupied
								n_inhabitant := o.inhabitant
								match n_inhabitant {
									Creature {
										n_creature := n_inhabitant as Creature

										n_is_alive := n_creature.life == .alive
										n_has_dispostion := n_creature.genome.social.has(sharing_xor_predator)
										
										n_has_similar_genome := has_similiar_genome(c.genome, n_creature.genome, 3)
										sharing_success := random_chance(sharing_success_chance)

										if n_is_alive && n_has_dispostion && n_has_similar_genome && sharing_success {

											neighbour_count += 1
											c.exchange_temp()
											tile.occupation = Occupied{c}
										}
									}
									else {}
								}
							}
							else {}
						}
					}

					if neighbour_count == 0 {
						c.loose_neighbour_temp()
						tile.occupation = Occupied{c}
					}
				}
				SomethingElse {}
			}
		}
		Empty {}
		BedRock {}
	}
}

fn creature_hunts(mut app App, mut row []GridTile, mut tile GridTile, i int, j int) {
	match tile.occupation {
		Empty {}
		BedRock {}
		Occupied {
			occupation := tile.occupation as Occupied
			mut inhabitant := occupation.inhabitant

			match inhabitant {
				Creature {
					mut c := occupation.inhabitant as Creature
					if !c.genome.social.has(.predator) {
						return
					}
					if c.life == .dead || c.genome.movement == .unable {
						return
					}

					mut chance_of_hunting := match c.genome.metabolism {
						.slow { rand.int_in_range(4, 64) }
						.normal { rand.int_in_range(4, 32) }
						.fast { rand.int_in_range(4, 8) }
					}

					chance_of_hunting = if c.temp < 20 {
						chance_of_hunting / 2
					} else if c.temp < 15 {
						2
					} else {
						chance_of_hunting
					}

					match rand.int_in_range(0, chance_of_hunting) {
						0 {
							if c.genome.direction_sensor.has(.north) {
								hunt_direction(mut app, mut tile, mut c, Direction.north,
									i, j)
							}
						}
						1 {
							if c.genome.direction_sensor.has(.east) {
								hunt_direction(mut app, mut tile, mut c, Direction.east,
									i, j)
							}
						}
						2 {
							if c.genome.direction_sensor.has(.south) {
								hunt_direction(mut app, mut tile, mut c, Direction.south,
									i, j)
							}
						}
						3 {
							if c.genome.direction_sensor.has(.west) {
								hunt_direction(mut app, mut tile, mut c, Direction.west,
									i, j)
							}
						}
						else {}
					}
				}
				SomethingElse {}
			}
		}
	}
}

fn hunt_direction(mut app App, mut tile GridTile, mut inhabitant Creature, dir Direction, i int, j int) {
	row_index, tile_index := match_direction(dir, i, j)
	mut neighbour_row := app.grid[row_index] or { return }
	mut neighbour_tile := neighbour_row[tile_index] or { return }

	match neighbour_tile.occupation {
		Empty {}
		BedRock {}
		Occupied {
			o := neighbour_tile.occupation as Occupied
			mut n_creature := o.inhabitant as Creature

			if has_similiar_genome(inhabitant.genome, n_creature.genome, rand.int_in_range(1,4)) && inhabitant.temp > 10 {
				return
			}

			if n_creature.life == .dead {
				inhabitant.add_temp(2)
			} else if n_creature.genome.immune_system.has(.defender) {
				inhabitant.remove_temp(byte(rand.int_in_range(1, 5)))
				n_creature.remove_temp(byte(rand.int_in_range(1, 5)))

				if n_creature.genome.immune_system.has(.strong_defender) {
					inhabitant.remove_temp(byte(rand.int_in_range(1, 5)))
					n_creature.remove_temp(byte(rand.int_in_range(1, 3)))
				}
			} else {
				inhabitant.add_temp(n_creature.temp)
				n_creature.life = .dead
			}

			if n_creature.life == .dead {
				inhabitant.add_temp(n_creature.temp + 2)
				inhabitant.use_movement_energy()
				neighbour_tile.occupation = Occupied{inhabitant}
				app.grid[row_index][tile_index] = neighbour_tile
				tile.occupation = Empty{}
			}
		}
	}
}

fn creature_moves(mut app App, mut row []GridTile, mut tile GridTile, i int, j int) {
	match tile.occupation {
		Empty {}
		BedRock {}
		Occupied {
			occupation := tile.occupation as Occupied
			mut inhabitant := occupation.inhabitant

			match inhabitant {
				Creature {
					mut c := occupation.inhabitant as Creature

					if c.life == .dead || c.genome.movement == .unable {
						return
					}

					if c.genome.social.has(.predator) && c.temp > 20 && c.age < repro_age {
						return
					}
					
					mut chance_of_moving := match c.genome.metabolism {
						.slow { rand.int_in_range(4, 64) }
						.normal { rand.int_in_range(4, 32) }
						.fast { rand.int_in_range(4, 8) }
					}

					if c.genome.immune_system.has(.defender) {
						chance_of_moving = chance_of_moving * 5
					}

					if c.genome.social.has(.sharing) {
						if c.received_temp > 0 {
							chance_of_moving = chance_of_moving * c.received_temp
						}
					}

					match rand.int_in_range(0, chance_of_moving) {
						0 {
							if c.genome.direction_sensor.has(.north) {
								move_direction(mut app, mut tile, mut c, Direction.north,
									i, j)
							}
						}
						1 {
							if c.genome.direction_sensor.has(.east) {
								move_direction(mut app, mut tile, mut c, Direction.east,
									i, j)
							}
						}
						2 {
							if c.genome.direction_sensor.has(.south) {
								move_direction(mut app, mut tile, mut c, Direction.south,
									i, j)
							}
						}
						3 {
							if c.genome.direction_sensor.has(.west) {
								move_direction(mut app, mut tile, mut c, Direction.west,
									i, j)
							}
						}
						else {}
					}
				}
				SomethingElse {}
			}
		}
	}
}

fn move_direction(mut app App, mut tile GridTile, mut c Creature, dir Direction, i int, j int) {
	row_index, tile_index := match_direction(dir, i, j)
	mut neighbour_row := app.grid[row_index] or { []GridTile{} }
	mut neighbour_tile := neighbour_row[tile_index] or { create_bedrock() }

	match neighbour_tile.occupation {
		Empty {
			c.use_movement_energy()
			neighbour_tile.occupation = Occupied{c}
			tile.occupation = Empty{}
			app.grid[row_index][tile_index] = neighbour_tile

			if app.debug && c.is_debug() {
				debug_movement(mut app, tile, neighbour_tile)
			}
		}
		BedRock {}
		Occupied {}
	}
}

fn creature_reproduces(mut app App, mut row []GridTile, mut tile GridTile, i int, j int) {
	match tile.occupation {
		Occupied {
			occupation := tile.occupation as Occupied
			inhabitant := occupation.inhabitant

			match inhabitant {
				SomethingElse {}
				Creature {
					mut c := inhabitant as Creature
					if c.life == .dead || c.age < repro_age || c.temp < 5 {
						return
					}

					mut chance_of_reproducing := match c.genome.metabolism {
						.slow { rand.u32_in_range(4, 64) }
						.normal { rand.u32_in_range(4, 32) }
						.fast { rand.u32_in_range(4, 8) }
					}

					chance_of_reproducing = match c.genome.ageing {
						.faster { u32(f32(chance_of_reproducing) * 0.8) }
						.fast { u32(f32(chance_of_reproducing) * 0.9) }
						.normal { u32(f32(chance_of_reproducing) * 1.1) }
						.slow { u32(f32(chance_of_reproducing) * 1.3) }
						.slower { u32(f32(chance_of_reproducing) * 1.5) }
					}

					effective_repro_cost := match c.genome.metabolism {
						.slow { byte(rand.int_in_range(repro_cost - 2, repro_cost + 2)) }
						.normal { byte(rand.int_in_range(repro_cost, repro_cost + 4)) }
						.fast { byte(rand.int_in_range(repro_cost + 2, repro_cost + 8)) }
					}

					// if inhabitant.genome.social.has(.sharing) {
					// 	if inhabitant.received_temp > 0 {
					// 		chance_of_reproducing = chance_of_reproducing * inhabitant.received_temp
					// 	}
					// }

					match rand.u32_in_range(0, chance_of_reproducing) {
						0 {
							mut empty_neighbours := []GridTile{}
							mut neighbours := []GridTile{}
							mut indicies_empty := [][]int{}
							mut indicies_neighbours := [][]int{}

							mut directions := [Direction.north, .east, .south, .west]
							rutil.shuffle(mut directions, 0)

							for _ in 0 .. 4 {
								dir := directions.pop()

								if c.genome.direction_sensor.has(match_direction_to_gene(dir)) {
									row_index, tile_index := match_direction(dir, i, j)
									mut neighbour_row := app.grid[row_index] or { continue }
									mut neighbour_tile := neighbour_row[tile_index] or { continue }

									match neighbour_tile.occupation {
										Occupied {
											neighbours << neighbour_tile
											indicies_neighbours << [row_index, tile_index]
										}
										Empty {
											empty_neighbours << neighbour_tile
											indicies_empty << [row_index, tile_index]
										}
										else {
											continue
										}
									}
								}
							}

							if neighbours.len > 0 && empty_neighbours.len > 0 {
								for n := 0; n < neighbours.len; n++ {
									mut neighbour := neighbours.pop()
									a_index := indicies_neighbours.pop()

									mut n_occupation := neighbour.occupation as Occupied
									mut neighbour_c := n_occupation.inhabitant as Creature

									if neighbour_c.life == .dead || neighbour_c.age < repro_age {
										continue
									}

									mut empty_neighbour := empty_neighbours.pop()
									e_index := indicies_empty.pop()
									
									match empty_neighbour.occupation {
										Empty {
											mut genome := inherit_genome(c.genome, neighbour_c.genome)
											genome = apply_genome_mutations(mut genome)
											mut child := init_creature(genome: genome)
											child.generation = c.generation + 1
											empty_neighbour.occupation = Occupied{child}
											app.grid[e_index[0]][e_index[1]] = empty_neighbour
										}
										else {
											panic('empty neighbour_c is not empty')
										}
									}
									c.reproduced = true
									c.remove_temp(effective_repro_cost)
									tile.occupation = Occupied{c}

									neighbour_c.reproduced = true
									neighbour.occupation = Occupied{neighbour_c}

									app.grid[a_index[0]][a_index[1]] = neighbour
									break
								}
							}
						}
						else {}
					}
				}
			}
		}
		else {}
	}
}

fn match_direction(dir Direction, i int, j int) (int, int) {
	row_index, tile_index := match dir {
		.north { i - 1, j }
		.east { i, j + 1 }
		.south { i + 1, j }
		.west { i, j - 1 }
	}
	return row_index, tile_index
}

fn match_direction_to_gene(dir Direction) DirectionSensorGene {
	return match dir {
		.north { DirectionSensorGene.north }
		.east { DirectionSensorGene.east }
		.south { DirectionSensorGene.south }
		.west { DirectionSensorGene.west }
	}
}

fn debug_movement(mut app App, tile GridTile, neighbour_tile GridTile) {
	if app.debug_grid.len > 1000 {
		app.debug_grid = [][]DebugGridTile{}
	}
	debug_tile := [DebugGridTile{
		x: tile.x
		y: tile.y
		color: gx.black
	}, DebugGridTile{
		x: neighbour_tile.x
		y: neighbour_tile.y
		color: gx.black
	}]
	app.debug_grid << debug_tile
}

fn color_space(g Genome) gx.Color {
	mut c := match g.metabolism {
		.slow { gx.rgba(0x0, 0x0, 0x5b, 0xff) }
		.normal { gx.rgba(0x0, 0x5b, 0x0, 0xff) }
		.fast { gx.rgba(0x5b, 0x0, 0x0, 0xff) }
	}

	if g.social.has(.predator) {
		c = gx.rgba(c.r + 0x90, c.g, c.b, 0xff)
	}

	if g.social.has(.sharing) {
		c = gx.rgba(c.r, c.g + 0x60, c.b, 0xff)
	}

	if g.immune_system.has(.defender) {
		c = gx.rgba(c.r, c.g - 0x40, c.b + 0x60, 0xff)
	}

	c = match g.mutation_rate {
		.slower {gx.rgba(c.r + 0x10, c.g + 0x10, c.b + 0x10, 0xff)}
		.slow {gx.rgba(c.r + 0x12, c.g + 0x12, c.b + 0x12, 0xff)}
		.normal {gx.rgba(c.r, c.g, c.b, 0xff)}
		.fast {gx.rgba(c.r + 0x22, c.g + 0x22, c.b + 0x22, 0xff)}
		.faster {gx.rgba(c.r + 0x2A, c.g + 0x2A, c.b + 0x2A, 0xff)}
		.insane {gx.rgba(c.r + 0x32, c.g + 0x32, c.b + 0x32, 0xff)}
	}

	c = color_range(c.r, c.g, c.b)

	c = match g.ageing {
		.faster { gx.rgba(c.r, c.g, c.b, 0xff - 0x2A) }
		.fast { gx.rgba(c.r, c.g, c.b, 0xff - 0x22) }
		.normal { gx.rgba(c.r, c.g, c.b, 0xff - 0x12) }
		.slow { gx.rgba(c.r, c.g, c.b, 0xff - 0x10) }
		.slower { gx.rgba(c.r, c.g, c.b, 0xff) }
	}

	return c
}

fn color_range(r byte, g byte, b byte) gx.Color {
	cr := [r, g, b].map(fn (b byte) byte {
		if b < lower_color_space {
			return lower_color_space + (lower_color_space - b)
		} else if b > upper_color_space {
			return upper_color_space - (b - upper_color_space)
		} else {
			return b
		}
	})

	return gx.rgb(cr[0], cr[1], cr[2])
}

fn create_bedrock() GridTile {
	return GridTile{
		occupation: BedRock{}
	}
}

fn debug_genome() Genome {
	return Genome{
		movement: .able
		direction_sensor: .north | .east | .south | .west
		metabolism: .normal
		social: .normal
		ageing: .slower
		immune_system: .normal
		mutation_rate: .normal
	}
}

fn has_similiar_genome(g1 &Genome, g2 &Genome, range int) bool {
	g1b_index := &byte(g1)
	g2b_index := &byte(g2)
	mut c := 0
	for i := 0; i < sizeof(g1b_index); i++ {
		if c >= range {
			return false
		}
		c += unsafe { g1b_index[i] - g2b_index[i] }
	}
	return c < range && c > (-range)
}

fn rand_genome() Genome {
	able_to_move := rand.int_in_range(0, 5)
	mut movement_gene := if able_to_move in [0, 2] { MovementGene.able } else { MovementGene.unable }
	mut direction_sensor := DirectionSensorGene.center

	for i in 0 .. 4 {
		if rand.int_in_range(0, 4) in [0, 1] {
			match i {
				0 { direction_sensor = direction_sensor | .north }
				1 { direction_sensor = direction_sensor | .east }
				2 { direction_sensor = direction_sensor | .south }
				3 { direction_sensor = direction_sensor | .west }
				else { panic('Invalid direction sensor index') }
			}
		}
	}

	metabolism := match rand.int_in_range(0, 3) {
		0 { MetabolismGene.normal }
		1 { MetabolismGene.fast }
		2 { MetabolismGene.slow }
		else { panic('Invalid metabolism gene index') }
	}

	social := match rand.int_in_range(0, 20) {
		0 { SocialGene.sharing }
		1 { SocialGene.sharing }
		2 { SocialGene.sharing }
		3 { SocialGene.sharing }
		10 { SocialGene.predator }
		11 { SocialGene.predator }
		else { SocialGene.normal }
	}

	ageing := match rand.int_in_range(0, 5) {
		0 { AgeingGene.faster }
		1 { AgeingGene.fast }
		2 { AgeingGene.normal }
		3 { AgeingGene.slow }
		4 { AgeingGene.slower }
		else { panic('Invalid ageing gene index') }
	}

	immune_system := match rand.int_in_range(0, 32) {
		0 { ImmuneSystemGene.defender }
		1 { ImmuneSystemGene.defender }
		2 { ImmuneSystemGene.defender }
		3 { ImmuneSystemGene.strong_defender }
		4 { ImmuneSystemGene.defender | ImmuneSystemGene.strong_defender }
		else { ImmuneSystemGene.normal }
	}

	mutation_rate := match rand.int_in_range(0, 15) {
		0 { MutationRateGene.slower }
		1 { MutationRateGene.slow }
		2 { MutationRateGene.normal }
		3 { MutationRateGene.fast }
		4 { MutationRateGene.faster }
		5 { MutationRateGene.insane }
		else { MutationRateGene.normal }
	}

	return Genome{
		movement: movement_gene
		direction_sensor: direction_sensor
		metabolism: metabolism
		social: social
		ageing: ageing
		immune_system: immune_system
		mutation_rate: mutation_rate
	}
}

fn inherit_genome(g1 Genome, g2 Genome) Genome {
	// TODO: Some genes should be reduced or improved by one parent instead of picking
	// one random of the parents
	mut movement_gene := g1.movement | g2.movement

	mut metabolism_genes := [g1.metabolism, g2.metabolism]
	rutil.shuffle(mut metabolism_genes, 0)

	added_s_genes := g1.social | g2.social
	social_gene := if added_s_genes.all(.predator | .sharing) {
		if random_chance(49) {
			(SocialGene.normal | SocialGene.predator) & added_s_genes
		} else {
			(SocialGene.normal | SocialGene.sharing) & added_s_genes
		}
	} else {
		g1.social | g2.social
	}

	mut ageing_genes := [g1.ageing, g2.ageing]
	rutil.shuffle(mut ageing_genes, 0)

	immune_gene := if (g1.immune_system | g2.immune_system).all(.defender | .strong_defender) {
		ImmuneSystemGene.defender | ImmuneSystemGene.strong_defender
	} else {
		mut immune_genes := [g1.immune_system, g2.immune_system]
		rutil.shuffle(mut immune_genes, 0)
		immune_genes[0]
	}


	mut faster_mutation_gene, slower_mutation_gene := if int(g2.mutation_rate) > int(g1.mutation_rate) {
		g2.mutation_rate, g1.mutation_rate
	} else if int(g1.mutation_rate) > int(g2.mutation_rate) {
		g1.mutation_rate, g2.mutation_rate
	} else {
		g1.mutation_rate, g1.mutation_rate
	}

	mut mutation_rate := MutationRateGene.normal
	mut new_mutation_rate := if random_chance(50) {
		faster_mutation_gene
	} else {
		slower_mutation_gene
	}

	if faster_mutation_gene.has(.fast) {
		if slower_mutation_gene.has(.slow) {
			new_mutation_rate = .normal
		} else if slower_mutation_gene.has(.slower) {
			new_mutation_rate = .slow
		} else {
			new_mutation_rate = faster_mutation_gene
		}
	}

	if faster_mutation_gene.has(.faster) {
		if slower_mutation_gene.has(.slow) {
			new_mutation_rate = .fast
		} else if slower_mutation_gene.has(.slower) {
			new_mutation_rate = .normal
		} else {
			new_mutation_rate = faster_mutation_gene
		}
	}

	if faster_mutation_gene.has(.insane) {
		if slower_mutation_gene.has(.slow) {
			new_mutation_rate = .faster
		} else if slower_mutation_gene.has(.slower) {
			new_mutation_rate = .fast
		} else {
			new_mutation_rate = faster_mutation_gene
		}
	}

	if g1.mutation_rate == g2.mutation_rate {
		mutation_rate = g1.mutation_rate
	} else if random_chance(65) {
		mutation_rate = new_mutation_rate
	}

	return Genome{
		movement: movement_gene
		direction_sensor: g1.direction_sensor | g2.direction_sensor
		metabolism: metabolism_genes[0]
		social: social_gene
		ageing: ageing_genes[0]
		immune_system: immune_gene
		mutation_rate: mutation_rate
	}
}

fn random_chance(c byte) bool {
	return rand.int_in_range(0, 100) < c
}

fn apply_genome_mutations(mut g Genome) Genome {
	mutation_rate := match g.mutation_rate {
		.slower { 3500 }
		.slow { 3000 }
		.normal { 2500 }
		.fast { 1850 }
		.faster { 1250 }
		.insane { 75 }
	}

	mut directions := [DirectionSensorGene.center, DirectionSensorGene.north, 
	DirectionSensorGene.south, DirectionSensorGene.east, DirectionSensorGene.west]
	rutil.shuffle(mut directions, 0)
	mut direction_mutation := DirectionSensorGene{}
	for j in 0..rand.int_in_range(0, 5) {
		direction_mutation = direction_mutation | directions[j]
	}

	match rand.int_in_range(0, mutation_rate) {
		0 { g.movement = MovementGene.unable }
		1 { g.movement = MovementGene.able }
		2 { g.direction_sensor = g.direction_sensor | DirectionSensorGene.center }
		3 { g.direction_sensor = g.direction_sensor | DirectionSensorGene.north }
		4 { g.direction_sensor = g.direction_sensor | DirectionSensorGene.east }
		5 { g.direction_sensor = g.direction_sensor | DirectionSensorGene.south }
		6 { g.direction_sensor = g.direction_sensor | DirectionSensorGene.west }
		7 { g.metabolism = MetabolismGene.fast }
		8 { g.metabolism = MetabolismGene.normal }
		9 { g.metabolism = MetabolismGene.slow }
		10 { g.social = SocialGene.sharing }
		11 { g.social = SocialGene.normal }
		12 { g.ageing = AgeingGene.faster }
		13 { g.ageing = AgeingGene.fast }
		14 { g.ageing = AgeingGene.normal }
		15 { g.ageing = AgeingGene.slow }
		16 { g.social = SocialGene.predator }
		17 { g.immune_system = ImmuneSystemGene.defender }
		18 { g.immune_system = ImmuneSystemGene.normal }
		19 { g.immune_system = g.immune_system | ImmuneSystemGene.strong_defender }
		20 { g.mutation_rate = MutationRateGene.normal }
		21 { g.mutation_rate = MutationRateGene.slower }
		22 { g.mutation_rate = MutationRateGene.slow }
		23 { g.mutation_rate = MutationRateGene.faster }
		24 { g.mutation_rate = MutationRateGene.fast }
		25 { g.mutation_rate = MutationRateGene.insane }
		26 { g.direction_sensor = direction_mutation }
		else {}
	}
	return g
}