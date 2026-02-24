#!/usr/bin/env python3
"""
Script to safely remove harness tests from Xcode project
"""

import re
import sys

def remove_harness_tests_from_project():
    project_file = "osx-ide.xcodeproj/project.pbxproj"
    
    # Read the project file
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Patterns to remove harness test references
    patterns_to_remove = [
        # Remove the file reference
        r'\t\t7A11AA032F90000100C0DE01 /\* osx-ideHarnessTests\.xctest \*/ = \{isa = PBXFileReference; explicitFileType = wrapper\.cfbundle; includeInIndex = 0; path = "osx-ideHarnessTests\.xctest"; sourceTree = BUILT_PRODUCTS_DIR; \};\n',
        
        # Remove the container item proxy
        r'\t\t7A11AA012F90000100C0DE01 /\* PBXContainerItemProxy \*/ = \{[^}]*\};\n',
        
        # Remove the file system synchronized group
        r'\t\t7A11AA042F90000100C0DE01 /\* osx-ideHarnessTests \*/ = \{[^}]*\};\n',
        
        # Remove from main group
        r'\t\t\t\t7A11AA042F90000100C0DE01 /\* osx-ideHarnessTests \*/,\n',
        
        # Remove from products group
        r'\t\t\t\t7A11AA032F90000100C0DE01 /\* osx-ideHarnessTests\.xctest \*/,\n',
        
        # Remove the target
        r'\t\t7A11AA082F90000100C0DE01 /\* osx-ideHarnessTests \*/ = \{[^}]*\};\n',
        
        # Remove from project targets
        r'\t\t\t\t7A11AA082F90000100C0DE01 /\* osx-ideHarnessTests \*/,\n',
        
        # Remove the target dependency
        r'\t\t\t\t7A11AA022F90000100C0DE01 /\* PBXTargetDependency \*/,\n',
        
        # Remove the build configuration list
        r'\t\t7A11AA0B2F90000100C0DE01 /\* Build configuration list for PBXNativeTarget "osx-ideHarnessTests" \*/ = \{[^}]*\};\n',
        
        # Remove build configurations
        r'\t\t7A11AA092F90000100C0DE01 /\* Debug \*/ = \{[^}]*PRODUCT_BUNDLE_IDENTIFIER = "tdc\.osx-ideHarnessTests"[^}]*\};\n',
        r'\t\t7A11AA0A2F90000100C0DE01 /\* Release \*/ = \{[^}]*PRODUCT_BUNDLE_IDENTIFIER = "tdc\.osx-ideHarnessTests"[^}]*\};\n',
    ]
    
    # Apply the patterns
    modified_content = content
    for pattern in patterns_to_remove:
        modified_content = re.sub(pattern, '', modified_content, flags=re.MULTILINE | re.DOTALL)
    
    # Write back the modified content
    with open(project_file, 'w') as f:
        f.write(modified_content)
    
    print("Harness tests removed from Xcode project")

if __name__ == "__main__":
    remove_harness_tests_from_project()
