local Layout={}
function Layout.detailsPlacement(available_height,line_height,left_width)
  local enough_height=(tonumber(available_height) or 0)>=(tonumber(line_height) or 0)*8
  local enough_width=left_width==nil or (tonumber(left_width) or 0)>=420
  return enough_height and enough_width and "left" or "right"
end
function Layout.detailsCardRows(columns) return tonumber(columns)==2 and 11 or 7 end
function Layout.detailsFit(rail_bottom,inventory_y,details_height,minimum_inventory_height)
  return (tonumber(rail_bottom) or 0)-(tonumber(details_height) or 0)-12-(tonumber(inventory_y) or 0)>=(tonumber(minimum_inventory_height) or 0)
end
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
local function metrics(width,height,layout)
  layout.console_width=width-layout.left-layout.right
  layout.body_font=clamp(width/100,16,22); layout.small_font=clamp((layout.body_font-2)*2,28,40); layout.heading_font=clamp(layout.body_font+5,21,27)
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
  return layout
end
function Layout.compute(width,height)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  local rail=math.floor(width*.17)
  if width>=1400 then return metrics(width,height,{mode="wide",left=rail,right=rail,top=74,bottom=0,show_character_rail=true,show_room_compass=height>=700,vitals_side="left"}) end
  if width>=1000 then return metrics(width,height,{mode="medium",left=rail,right=rail,top=66,bottom=0,show_character_rail=true,show_room_compass=height>=650,vitals_side="left"}) end
  return metrics(width,height,{mode="compact",left=0,right=0,top=116,bottom=0,show_character_rail=false,show_room_compass=false,vitals_side="compact"})
end
return Layout
