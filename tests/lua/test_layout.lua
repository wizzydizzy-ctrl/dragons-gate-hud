local Layout=require("layout")
test("wide screens reserve seventeen percent for each HUD rail",function()
  local r=Layout.compute(1920,1080); eq(r.mode,"wide"); eq(r.left,326); eq(r.right,326); eq(r.console_width,1268); eq(r.top,74); eq(r.show_character_rail,true); eq(r.vitals_side,"left")
end)
test("medium screens preserve the seventeen sixty-six seventeen split",function()
  local r=Layout.compute(1200,800); eq(r.mode,"medium"); eq(r.left,204); eq(r.right,204); eq(r.console_width,792); eq(r.top,66); eq(r.show_character_rail,true); eq(r.show_room_compass,true); eq(r.vitals_side,"left")
end)
test("compact screens move all status out of side rails",function()
  local r=Layout.compute(760,700); eq(r.mode,"compact"); eq(r.left,0); eq(r.right,0); eq(r.top,116); eq(r.bottom,0); eq(r.show_room_compass,false)
end)
test("duplicate bottom information row reserves no console space",function()
  for _,size in ipairs({{760,700},{1200,800},{2560,1400}}) do eq(Layout.compute(size[1],size[2]).bottom,0) end
end)
test("layout leaves sixty-six percent of rail layouts for the main console",function()
  for _,w in ipairs({1000,1024,1366,1400,1600,1920,2056,2560,3840}) do local r=Layout.compute(w,900); eq(r.console_width>=w*.66,true) end
end)
test("responsive typography remains readable at every breakpoint",function()
  local compact=Layout.compute(760,700); local medium=Layout.compute(1200,800); local wide=Layout.compute(2056,1177); local ultra=Layout.compute(3840,2160)
  eq(compact.body_font>=16,true); eq(medium.body_font>=16,true); eq(wide.body_font>=20,true); eq(ultra.body_font>=22,true)
  eq(wide.heading_font>wide.body_font,true); eq(wide.gauge_height>=26,true); eq(wide.panel_padding>=16,true)
  eq(wide.small_font>=(wide.body_font-2)*2,true); eq(wide.gauge_height>=wide.small_font+10,true)
end)
test("component metrics grow without overflowing narrow layouts",function()
  for _,size in ipairs({{760,700},{900,650},{1200,800},{2056,1177},{3840,2160}}) do
    local r=Layout.compute(size[1],size[2]); eq(r.body_font<=22,true); eq(r.heading_font<=28,true); eq(r.panel_padding<=24,true); eq(r.gauge_height<=56,true)
  end
end)

test("content boxes scale with typography instead of clipping",function()
  local compact=Layout.compute(760,700); local wide=Layout.compute(1920,1080)
  eq(wide.title_height>=wide.heading_font+24,true)
  eq(wide.status_height>=wide.body_font*4+32,true)
  eq(wide.room_height>=wide.heading_font+wide.body_font*6+44,true)
  eq(wide.exit_height>=wide.small_font+12,true)
  eq(wide.status_height>compact.status_height,true)
  eq(wide.identity_height>=wide.heading_font+wide.body_font*6+48,true)
end)

test("new cards derive dimensions from responsive fonts",function()
  for _,size in ipairs({{760,700},{1200,800},{2056,1177},{3840,2160}}) do
    local r=Layout.compute(size[1],size[2]); eq(r.inventory_row_height>=r.inventory_font+8,true); eq(r.details_line_height>=r.body_font+4,true); eq(r.compass_cell>=r.compass_font+10,true); eq(r.utility_height>=r.utility_font+10,true); eq(r.console_width>=size[1]*.66,true)
  end
end)
test("character details move to the roomier rail when the left stack is short",function()
  eq(Layout.detailsPlacement(240,26,500),"left")
  eq(Layout.detailsPlacement(240,26,300),"right")
  eq(Layout.detailsPlacement(180,26,500),"right")
  eq(Layout.detailsPlacement(120,26,500),"right")
end)
test("two-column character details reserve every rendered row",function()
  eq(Layout.detailsCardRows(2),11)
  eq(Layout.detailsCardRows(4),7)
end)
test("lower-left vitals stack uses compact readable gauge typography",function()
  local r=Layout.compute(1920,1080)
  eq(r.lower_scale,.8)
  eq(r.lower_title_height,0)
  eq(r.lower_small_font<=r.lower_body_font+1,true)
  eq(r.lower_gauge_height>=r.lower_small_font+12,true)
  for _,pair in ipairs({
    {r.lower_body_font,r.body_font},{r.lower_heading_font,r.heading_font},
    {r.lower_panel_padding,r.panel_padding},{r.lower_row_gap,r.row_gap},
    {r.lower_status_height,r.status_height},{r.lower_room_height,r.room_height},{r.lower_compass_cell,r.compass_cell},
    {r.lower_utility_height,r.utility_height}
  }) do eq(pair[1],math.floor(pair[2]*.8+.5)) end
end)
