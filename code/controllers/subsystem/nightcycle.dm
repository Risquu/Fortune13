/*  6:00 AM 	- 	21600
	6:45 AM 	- 	24300
	11:45 AM 	- 	42300
	4:45 PM 	- 	60300
	9:45 PM 	- 	78300
	10:30 PM 	- 	81000 */
#define CYCLE_SUNRISE 	216000
#define CYCLE_MORNING 	243000
#define CYCLE_DAYTIME 	423000
#define CYCLE_AFTERNOON 603000
#define CYCLE_SUNSET 	783000
#define CYCLE_NIGHTTIME 810000

#define SUNRISE 0
#define MORNING 1
#define DAYTIME 2
#define AFTERNOON 3
#define SUNSET 4
#define NIGHTTIME 5
#define DAY_END 6

SUBSYSTEM_DEF(nightcycle)
	name = "Day/Night Cycle"
	wait = 10 SECONDS
	// Control vars
	var/current_time = DAYTIME
	var/current_sun_color = "#FFFFFF"
	var/current_sun_power = 230

	// Variables for badmining
	var/sunrise_sun_color = "#ffd1b3"
	var/sunrise_sun_power = 80
	var/morning_sun_color = "#fff2e6"
	var/morning_sun_power = 160
	var/daytime_sun_color = "#FFFFFF"
	var/daytime_sun_power = 230
	var/afternoon_sun_color = "#fff2e6"
	var/afternoon_sun_power = 160
	var/sunset_sun_color = "#ffcccc"
	var/sunset_sun_power = 80
	var/nighttime_sun_color = "#00111a"
	var/nighttime_sun_power = 10
	/// How does it take to get darker or brighter each step.
	var/cycle_transition_time = 30 SECONDS
	/// If defined with any number besides null it will determine how long each cycle lasts.
	var/custom_cycle_wait = null
	var/last_custom_cycle = 0

	// Light objects
	var/atom/movable/sunlight/sunlight_source_object = new()
	var/list/sunlight_border_objects = list()


/datum/controller/subsystem/nightcycle/Initialize(start_timeofday)
	. = ..()
	sunlight_source_object.alpha = current_sun_power
	sunlight_source_object.color = current_sun_color


/datum/controller/subsystem/nightcycle/fire(resumed = FALSE)
	var/new_time
	
	if (!isnull(custom_cycle_wait))
		if(last_custom_cycle + custom_cycle_wait >= world.time)
			return
		last_custom_cycle = world.time
		new_time = (current_time + 1) % DAY_END
	else
		switch (station_time())
			if (CYCLE_SUNRISE to CYCLE_MORNING)
				new_time = SUNRISE
			if (CYCLE_MORNING to CYCLE_DAYTIME)
				new_time = MORNING
			if (CYCLE_DAYTIME to CYCLE_AFTERNOON)
				new_time = DAYTIME
			if (CYCLE_AFTERNOON to CYCLE_SUNSET)
				new_time = AFTERNOON
			if (CYCLE_SUNSET to CYCLE_NIGHTTIME)
				new_time = SUNSET
			else
				new_time = NIGHTTIME
		if (new_time == current_time)
			return

	switch (new_time)
		if (SUNRISE)
			current_sun_color = sunrise_sun_color
			current_sun_power = sunrise_sun_power
		if (MORNING)
			current_sun_color = morning_sun_color
			current_sun_power = morning_sun_power
			for(var/obj/structure/lamp_post/lamp as anything in GLOB.lamppost)
				lamp.icon_state = "[initial(lamp.icon_state)]"
				lamp.set_light(0)
		if (DAYTIME)
			current_sun_color = daytime_sun_color
			current_sun_power = daytime_sun_power
		if (AFTERNOON)
			current_sun_color = afternoon_sun_color
			current_sun_power = afternoon_sun_power
		if (SUNSET)
			current_sun_color = sunset_sun_color
			current_sun_power = sunset_sun_power
			for(var/obj/structure/lamp_post/lamp as anything in GLOB.lamppost)
				lamp.icon_state = "[initial(lamp.icon_state)]-on"
				lamp.set_light(lamp.on_range, lamp.on_power, lamp.light_color)
		if(NIGHTTIME)
			current_sun_color = nighttime_sun_color
			current_sun_power = nighttime_sun_power
		else
			CRASH("Invalid new_time returned from station_time()")

	current_time = new_time

	var/atom/movable/sunlight/light_object = sunlight_source_object
	animate(light_object, alpha = current_sun_power, color = current_sun_color, time = cycle_transition_time)
	for(var/key in sunlight_border_objects)
		animate(sunlight_border_objects[key], alpha = current_sun_power, color = current_sun_color, time = cycle_transition_time)


/datum/controller/subsystem/nightcycle/proc/get_border_object(object_key)
	. = sunlight_border_objects["[object_key]"]
	if(!.)
		. = new /atom/movable/sunlight(null, current_sun_power, current_sun_color, object_key)
		sunlight_border_objects["[object_key]"] = .


/atom/movable/sunlight
	name = ""
	icon = 'icons/effects/light_overlays/sunlight_source.dmi'
	icon_state = "light"
	move_resist = INFINITY
	plane = O_LIGHTING_VISUAL_PLANE
	appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	invisibility = INVISIBILITY_LIGHTING
	alpha = 0
	vis_flags = NONE


/atom/movable/sunlight/Initialize(mapload, alpha = null, color = null, neighbors = null)
	. = ..()
	if(!isnull(neighbors))
		icon = 'icons/effects/light_overlays/border_lights.dmi'
		icon_state = "[neighbors]"
	if(!isnull(alpha))
		src.alpha = alpha
	if(!isnull(color))
		src.color = color


///Proc to initialize sunlight source turfs and affect non-source neighbors.
/turf/proc/setup_sunlight_source()
	vis_contents += SSnightcycle.sunlight_source_object
	luminosity = 1
	for(var/dir in GLOB.alldirs)
		var/turf/neighbor = get_step(src, dir)
		if(!neighbor || neighbor.sunlight_state != NO_SUNLIGHT)
			continue
		neighbor.sunlight_state = SUNLIGHT_BORDER
		if(neighbor.flags_1 & INITIALIZED_1)
			neighbor.smooth_sunlight_border()


#define SUNLIGHT_ADJ_IN_DIR(source, junction, direction, direction_flag) \
	do { \
		var/turf/neighbor = get_step(source, direction); \
		if(!neighbor || neighbor.sunlight_state != SUNLIGHT_SOURCE) { \
			continue; \
		}; \
		junction |= direction_flag; \
	} while(FALSE)

/// Scans neighbors for sunlight sources and sets up the proper object to handle it.
/turf/proc/smooth_sunlight_border()
	var/new_junction = NONE
	for(var/direction in GLOB.cardinals) //Cardinal case first.
		SUNLIGHT_ADJ_IN_DIR(src, new_junction, direction, direction)
	SUNLIGHT_ADJ_IN_DIR(src, new_junction, NORTHWEST, NORTHWEST_JUNCTION)
	SUNLIGHT_ADJ_IN_DIR(src, new_junction, NORTHEAST, NORTHEAST_JUNCTION)
	SUNLIGHT_ADJ_IN_DIR(src, new_junction, SOUTHWEST, SOUTHWEST_JUNCTION)
	SUNLIGHT_ADJ_IN_DIR(src, new_junction, SOUTHEAST, SOUTHEAST_JUNCTION)
	if(new_junction == border_neighbors)
		return // No change.
	if(!isnull(border_neighbors)) // Different and non-null, there was a change.
		vis_contents -= SSnightcycle.get_border_object(border_neighbors)
	if(new_junction == NONE)
		if(sunlight_state == SUNLIGHT_BORDER)
			sunlight_state = NO_SUNLIGHT
		if(lighting_object)
			luminosity = 0 // Luminosity now depends on dynamic lighting.
		return // No longer a sunlight border.
	border_neighbors = new_junction
	luminosity = 1
	var/atom/movable/sunlight/light_object = SSnightcycle.get_border_object(new_junction)
	vis_contents += light_object

#undef SUNLIGHT_ADJ_IN_DIR
#undef CYCLE_SUNRISE
#undef CYCLE_MORNING
#undef CYCLE_DAYTIME
#undef CYCLE_AFTERNOON
#undef CYCLE_SUNSET
#undef CYCLE_NIGHTTIME
#undef SUNRISE
#undef MORNING
#undef DAYTIME
#undef AFTERNOON
#undef SUNSET
#undef NIGHTTIME
#undef DAY_END
