local Layout={}
function Layout.detailsPlacement(available_height,line_height,left_width)
  local enough_height=(tonumber(available_height) or 0)>=(tonumber(line_height) or 0)*8
  local enough_width=left_width==nil or (tonumber(left_width) or 0)>=420
  return enough_height and enough_width and "left" or "right"
end
function Layout.detailsCardRows(columns) return 3 end
function Layout.detailsFit(rail_bottom,inventory_y,details_height,minimum_inventory_height)
  return (tonumber(rail_bottom) or 0)-(tonumber(details_height) or 0)-12-(tonumber(inventory_y) or 0)>=(tonumber(minimum_inventory_height) or 0)
end
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
local function chatMetrics(width,height,layout,settings)
  settings=type(settings)=="table" and settings or {}
  local default_percent=.21
  local target=tonumber(settings.target_height) or 240
  local minimum=tonumber(settings.min_height) or 160
  local maximum=tonumber(settings.max_height) or 320
  local percent=tonumber(settings.height_percent) or default_percent
  local minimum_console_remainder=math.max(1,math.floor(tonumber(settings.minimum_console_remainder) or 120))
  local chat_chrome_height=44
  local chat_output_minimum=16
  local chat_functional_minimum=chat_chrome_height+chat_output_minimum
  if maximum<minimum then maximum=minimum end
  layout.header_height=math.min(layout.top,math.max(0,height-chat_functional_minimum-1))
  local configured_height=clamp(height*percent*(target/(1080*default_percent)),minimum,maximum)
  local available=math.max(0,height-layout.header_height)
  local adaptive_console_remainder=math.min(minimum_console_remainder,math.max(1,available-chat_functional_minimum))
  local available_chat=math.min(math.max(0,available-1),math.max(chat_functional_minimum,available-adaptive_console_remainder))
  layout.minimum_console_remainder=minimum_console_remainder
  layout.chat_functional_minimum=chat_functional_minimum
  layout.chat_height=math.min(configured_height,available_chat)
  layout.chat_x=layout.left
  layout.chat_width=layout.console_width
  layout.chat_padding=8
  layout.chat_scrollbar_allowance=18
  layout.chat_font=clamp(width/148,11,15)
  layout.chat_character_width=math.max(6,layout.chat_font*.62)
  layout.chat_inner_width=math.max(1,layout.chat_width-(2*layout.chat_padding)-layout.chat_scrollbar_allowance)
  layout.chat_wrap_columns=math.max(30,math.floor(layout.chat_inner_width/layout.chat_character_width))
  layout.console_top=layout.header_height+layout.chat_height
  layout.console_remainder=math.max(0,height-layout.console_top)
  layout.chat_output_height=math.max(0,layout.chat_height-chat_chrome_height)
  layout.top=layout.console_top
  return layout
end
local function metrics(width,height,layout,chatSettings)
  layout.console_width=width-layout.left-layout.right
  layout.body_font=clamp(width/100,16,22); layout.small_font=clamp((layout.body_font-2)*2,28,40); layout.heading_font=clamp(layout.body_font+5,21,27)
  layout.attribute_strip_font=clamp(layout.console_width/100,10,14)
  layout.panel_padding=clamp(width/120,12,22); layout.gauge_height=clamp(layout.small_font+10,38,50); layout.row_gap=clamp(layout.body_font*.7,11,15)
  layout.title_height=layout.heading_font+30; layout.status_height=layout.body_font*4+40
  layout.room_height=layout.heading_font+layout.body_font*6+54; layout.exit_height=layout.small_font+16
  layout.identity_height=layout.heading_font+layout.body_font*6+56
  layout.inventory_font=clamp(layout.body_font-2,14,20); layout.inventory_row_height=layout.inventory_font+10
  layout.details_line_height=layout.body_font+6; layout.compass_font=clamp(layout.body_font,16,22); layout.compass_cell=layout.compass_font+14
  layout.utility_font=clamp(layout.body_font-4,12,18); layout.utility_height=layout.utility_font+12
  local function scaled(value) return math.floor(value*.8+.5) end
  layout.lower_scale=.8
  layout.lower_body_font=scaled(layout.body_font); layout.lower_small_font=layout.lower_body_font; layout.lower_heading_font=scaled(layout.heading_font)
  layout.lower_panel_padding=scaled(layout.panel_padding); layout.lower_gauge_height=layout.lower_small_font+14; layout.lower_row_gap=scaled(layout.row_gap)
  layout.lower_title_height=0; layout.lower_status_height=scaled(layout.status_height); layout.lower_room_height=scaled(layout.room_height)
  layout.lower_compass_font=scaled(layout.compass_font); layout.lower_compass_cell=scaled(layout.compass_cell)
  layout.lower_utility_font=scaled(layout.utility_font); layout.lower_utility_height=scaled(layout.utility_height); layout.lower_section_gap=scaled(44)
  layout.bottom=0; layout.window_height=height
  return chatMetrics(width,height,layout,chatSettings)
end
function Layout.compute(width,height,chatSettings)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  local rail=math.floor(width*.17)
  if width>=1400 then return metrics(width,height,{mode="wide",left=rail,right=rail,top=74,bottom=0,show_character_rail=true,show_room_compass=height>=700,vitals_side="left"},chatSettings) end
  if width>=1000 then return metrics(width,height,{mode="medium",left=rail,right=rail,top=66,bottom=0,show_character_rail=true,show_room_compass=height>=650,vitals_side="left"},chatSettings) end
  return metrics(width,height,{mode="compact",left=0,right=0,top=116,bottom=0,show_character_rail=false,show_room_compass=false,vitals_side="compact"},chatSettings)
end
return Layout
