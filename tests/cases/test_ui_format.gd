extends TestSuite


func test_time_is_minutes_and_seconds() -> void:
	assert_eq(UiFormat.time(0.0), "0:00")
	assert_eq(UiFormat.time(83.9), "1:23")
	assert_eq(UiFormat.time(420.0), "7:00")


func test_brief_labels_name_all_parts_up_to_the_limit() -> void:
	assert_eq(UiFormat.labels_brief(PackedStringArray(["battery_connector"])), "Battery Connector")
	assert_eq(UiFormat.labels_brief(PackedStringArray(["pentalobe_left", "pentalobe_right"]), 2), "Pentalobe Left, Pentalobe Right")


func test_brief_labels_summarize_beyond_the_limit() -> void:
	var tabs: PackedStringArray = ["battery_tab_top_right", "battery_tab_top_left", "battery_tab_bottom_right", "battery_tab_bottom_left"]
	assert_eq(UiFormat.labels_brief(tabs), "Battery Tab Top Right and 3 more")
	assert_eq(UiFormat.labels_brief(tabs, 2), "Battery Tab Top Right, Battery Tab Top Left and 2 more")
