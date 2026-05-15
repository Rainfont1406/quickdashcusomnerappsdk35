import 'package:emartconsumer/controller/osm_search_place_controller.dart';
import 'package:emartconsumer/theme/app_them_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OsmSearchPlacesApi extends StatelessWidget {
  const OsmSearchPlacesApi({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GetX<OsmSearchPlaceController>(
      init: OsmSearchPlaceController(),
      builder: (controller) {
        return Scaffold(
          backgroundColor: isDarkMode ? AppThemeData.surfaceDark : Colors.white,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: AppThemeData.primary500,
            leading: InkWell(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            title: Text(
              'Search Places',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: AppThemeData.medium),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppThemeData.grey900 : AppThemeData.grey50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDarkMode ? AppThemeData.grey900 : AppThemeData.grey200,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: controller.searchTxtController.value,
                    decoration: InputDecoration(
                      hintText: 'Search your location here',
                      hintStyle: TextStyle(
                        color: isDarkMode ? AppThemeData.grey600 : AppThemeData.grey400,
                        fontFamily: AppThemeData.regular,
                      ),
                      prefixIcon: Icon(Icons.search, color: AppThemeData.primary500),
                      suffixIcon: Obx(() => controller.searchText.value.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.cancel),
                              onPressed: () {
                                controller.searchTxtController.value.clear();
                                controller.searchText.value = '';
                                controller.suggestionsList.clear();
                              },
                            )
                          : const SizedBox.shrink()),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Obx(() {
                  if (controller.isLoading.value) {
                    return const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  } else if (controller.suggestionsList.isEmpty && controller.searchText.value.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          'No locations found',
                          style: TextStyle(
                            color: isDarkMode ? AppThemeData.grey600 : AppThemeData.grey400,
                            fontFamily: AppThemeData.regular,
                          ),
                        ),
                      ),
                    );
                  } else if (controller.suggestionsList.isNotEmpty) {
                    return Expanded(
                      child: ListView.builder(
                        itemCount: controller.suggestionsList.length,
                        itemBuilder: (context, index) {
                          final suggestion = controller.suggestionsList[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: isDarkMode ? AppThemeData.grey900 : Colors.white,
                            elevation: isDarkMode ? 0 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isDarkMode ? AppThemeData.grey800 : AppThemeData.grey200,
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.location_on, color: AppThemeData.primary500),
                              title: Text(
                                suggestion.displayName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppThemeData.medium,
                                  color: isDarkMode ? AppThemeData.grey50 : AppThemeData.grey900,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context, suggestion.searchInfo);
                              },
                            ),
                          );
                        },
                      ),
                    );
                  } else {
                    return const SizedBox.shrink();
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
