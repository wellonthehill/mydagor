float4 sky_color = (0.1, 0.1, 0.1, 0);
float4 from_sun_direction = (0.58, -0.58, 0.58, 0);
float4 sun_color_0 = (0.8, 0.75, 0.7, 0);

block(global_const) global_const_block
{
  (vs) {
    from_sun_direction@f3 = from_sun_direction;
    sun_color_0@f3 = sun_color_0;
    sky_color@f3 = sky_color;
  }
  (ps) {
    from_sun_direction@f3 = from_sun_direction;
    sun_color_0@f3 = sun_color_0;
    sky_color@f3 = sky_color;
  }
}
