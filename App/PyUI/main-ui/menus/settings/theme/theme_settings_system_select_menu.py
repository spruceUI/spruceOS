
from display.resize_type import get_next_resize_type
from menus.language.language import Language
from menus.settings.theme.theme_settings_menu_common import ThemeSettingsMenuCommon
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


class ThemeSettingsSystemSelectMenu(ThemeSettingsMenuCommon):
    def __init__(self):
        super().__init__()

    def build_options_list(self) -> list[GridOrListEntry]:
        option_list = []
        option_list.append(
            self.build_view_type_entry(Language.view_type(),
                                     Theme.get_view_type_for_system_select_menu,
                                     Theme.set_view_type_for_system_select_menu)
        )

        if(ViewType.TEXT_AND_IMAGE == Theme.get_view_type_for_system_select_menu()):
            option_list.append(
                self.build_numeric_entry(
                    primary_text=Language.img_width(),
                    get_value_func=Theme.get_list_system_select_img_width,
                    set_value_func=Theme.set_list_system_select_img_width
                )
            )
            option_list.append(
                            self.build_numeric_entry(
                                primary_text=Language.img_height(),
                                get_value_func=Theme.get_list_system_select_img_height,
                                set_value_func=Theme.set_list_system_select_img_height
                            )
                        )                       
        if(ViewType.CAROUSEL == Theme.get_view_type_for_system_select_menu()):        
            option_list.append(
                self.build_numeric_entry(Language.cols(),
                                        Theme.get_game_system_select_carousel_col_count,
                                        Theme.set_game_system_select_carousel_col_count)
            )

        if(ViewType.GRID == Theme.get_view_type_for_system_select_menu()):
            option_list.append(
                self.build_numeric_entry(Language.cols(),
                                        Theme.get_game_system_select_col_count,
                                        Theme.set_game_system_select_col_count)
            )
            option_list.append(
                self.build_numeric_entry(Language.rows(),
                                        Theme.get_game_system_select_row_count,
                                        Theme.set_game_system_select_row_count)
            )
            option_list.append(
                self.build_enabled_disabled_entry(Language.show_text(),
                                        Theme.get_system_select_show_text_grid_mode,
                                        Theme.set_system_select_show_text_grid_mode)
            )
            option_list.append(
                self.build_enabled_disabled_entry(Language.label("showSelBg", "Show Sel BG"),
                                        Theme.get_system_select_show_sel_bg_grid_mode,
                                        Theme.set_system_select_show_sel_bg_grid_mode)
            )
            option_list.append(
                self.build_enum_entry(
                    primary_text=Language.img_mode(),
                    get_value_func=Theme.get_grid_system_selected_resize_type,
                    set_value_func=Theme.set_grid_system_selected_resize_type,
                    get_next_enum_type=get_next_resize_type,
                    enum_section="resizeTypes"
                )
            ) 
            option_list.append(
                            self.build_numeric_entry(
                                primary_text=Language.img_width(),
                                get_value_func=Theme.get_grid_system_select_img_width,
                                set_value_func=Theme.set_grid_system_select_img_width
                            )
                        )                       
            option_list.append(
                            self.build_numeric_entry(
                                primary_text=Language.img_height(),
                                get_value_func=Theme.get_grid_system_select_img_height,
                                set_value_func=Theme.set_grid_system_select_img_height
                            )
                        )                  
            if(Theme.get_game_system_select_row_count() == 1):
                option_list.append(
                    self.build_enabled_disabled_entry(Language.label("wrapAround", "Wrap-Around"),
                                            Theme.get_system_select_grid_wrap_around_single_row,
                                            Theme.set_system_select_grid_wrap_around_single_row)
                )

        if(ViewType.FULLSCREEN_GRID == Theme.get_view_type_for_system_select_menu()):
            option_list.append(
                self.build_enabled_disabled_entry(Language.show_text(),
                                        Theme.get_system_select_render_full_screen_grid_text_overlay,
                                        Theme.set_system_select_render_full_screen_grid_text_overlay)
            )
            option_list.append(
                self.build_enum_entry(
                    primary_text=Language.label("resizeType", "Resize Type"),
                    get_value_func=Theme.get_full_screen_grid_system_select_menu_resize_type,
                    set_value_func=Theme.set_full_screen_grid_system_select_menu_resize_type,
                    get_next_enum_type=get_next_resize_type,
                    enum_section="resizeTypes"
                )
            )                
            
        if(ViewType.CAROUSEL == Theme.get_view_type_for_system_select_menu()):  
            option_list.append(
                self.build_enabled_disabled_entry(
                    primary_text=Language.label("percentageMode", "Percentage Mode"),
                    get_value_func=Theme.get_carousel_system_use_percentage_mode,
                    set_value_func=Theme.set_carousel_system_use_percentage_mode
                )
            )
            option_list.append(
                self.build_enabled_disabled_entry(Language.label("verticalCarousel", "Vertical Carousel"), 
                        Theme.get_system_select_use_vertical_carousel, 
                        Theme.set_system_select_use_vertical_carousel)
            )
            if(Theme.get_carousel_system_use_percentage_mode()):
                option_list.append(
                    self.build_percent_entry(
                        primary_text=Language.prim_img_width(),
                        get_value_func=Theme.get_carousel_system_select_primary_img_width,
                        set_value_func=Theme.set_carousel_system_select_primary_img_width
                    )
                )
                if (Theme.get_game_system_select_carousel_col_count() > 3):
                    option_list.append(
                        self.build_enabled_disabled_entry(
                            primary_text=Language.shrink_further_away(),
                            get_value_func=Theme.get_carousel_system_select_shrink_further_away,
                            set_value_func=Theme.set_carousel_system_select_shrink_further_away
                        )
                    )

                if (not Theme.get_carousel_system_select_shrink_further_away()):
                    option_list.append(
                        self.build_enabled_disabled_entry(
                            Language.label("sidesHangOff", "Sides Hang Off"),
                            Theme.get_carousel_system_select_sides_hang_off,
                            Theme.set_carousel_system_select_sides_hang_off)
                    )
            else:
                option_list.append(
                    self.build_numeric_entry(
                        Language.label("height", "Height") if Theme.get_system_select_use_vertical_carousel() else Language.label("width", "Width"),
                        Theme.get_carousel_system_fixed_width,
                        Theme.set_carousel_system_fixed_width)
                )
                option_list.append(
                    self.build_numeric_entry(
                        Language.label("selectedHeight", "Selected Height") if Theme.get_system_select_use_vertical_carousel() else Language.label("selectedWidth", "Selected Width"),
                        Theme.get_carousel_system_fixed_selected_width,
                        Theme.set_carousel_system_fixed_selected_width)
                )

            # Should restrict NONE if in use percentage mode but oh well
            option_list.append(
                self.build_enum_entry(
                                    primary_text=Language.label("imageResizeType", "Image Resize Type"),
                                    get_value_func=Theme.get_carousel_system_resize_type,
                                    set_value_func=Theme.set_carousel_system_resize_type,
                                    get_next_enum_type=get_next_resize_type,
                                    enum_section="resizeTypes"
                                )               
            )


            option_list.append(
                self.build_numeric_entry(Language.label("internalPadding", "Internal Padding"),
                                        Theme.get_carousel_system_x_pad,
                                        Theme.set_carousel_system_x_pad,
                                        min=0)
            )
            option_list.append(
                self.build_numeric_entry(Language.label("yOffset", "Y-Offset"),
                                        Theme.get_carousel_system_additional_y_offset,
                                        Theme.set_carousel_system_additional_y_offset,
                                        min=0)
            )
            option_list.append(
                self.build_numeric_entry(Language.label("selectedIconPositionOffset", "Selected Icon Position Offset"),
                                        Theme.get_carousel_system_selected_offset,
                                        Theme.set_carousel_system_selected_offset,
                                        min=0)
            )
            option_list.append(
                self.build_enabled_disabled_entry(Language.label("useSelectedImageInAnimation", "Use Selected Image In Animation"),
                                        Theme.get_carousel_use_selected_image_in_animation,
                                        Theme.set_carousel_use_selected_image_in_animation)
            )


            
            option_list.append(
                self.build_numeric_entry(Language.label("xOffset", "X-Offset"),
                                        Theme.get_carousel_system_external_x_offset,
                                        Theme.set_carousel_system_external_x_offset,
                                        min=-99999)
            )

        if(ViewType.CAROUSEL == Theme.get_view_type_for_system_select_menu() or ViewType.CAROUSEL == Theme.get_view_type_for_system_select_menu()):        
            option_list.append(
                self.build_enabled_disabled_entry(
                    Language.label("setTopBarText", "Set Top Bar Text"),
                    Theme.get_system_selection_set_top_bar_text,
                    Theme.set_system_selection_set_top_bar_text)
            )
            option_list.append(
                self.build_enabled_disabled_entry(
                    Language.label("setBottomBarText", "Set Bottom Bar Text"),
                    Theme.get_system_selection_set_bottom_bar_text,
                    Theme.set_system_selection_set_bottom_bar_text)
            )

        return option_list
