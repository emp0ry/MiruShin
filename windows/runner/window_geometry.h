#ifndef RUNNER_WINDOW_GEOMETRY_H_
#define RUNNER_WINDOW_GEOMETRY_H_

#include <windows.h>

#include <optional>

std::optional<RECT> LoadWindowGeometry();
void SaveWindowGeometry(HWND window);

#endif  // RUNNER_WINDOW_GEOMETRY_H_
