# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/kernel/kleaf/impl:common_providers.bzl", "ModuleSymversInfo")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "ddk_headers")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:kernel_module.bzl", "kernel_module")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")

def _ddk_module_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    module_symvers_restore_path = target_under_test[ModuleSymversInfo].restore_path
    asserts.true(
        env,
        target_under_test.label.name in module_symvers_restore_path,
        "Module.symvers is restored to {}, but it must contain {} to distinguish with other modules in the same package".format(
            module_symvers_restore_path,
            target_under_test.label.name,
        ),
    )

    expected_inputs = sets.make(ctx.files.expected_inputs)

    action = None
    for a in target_under_test.actions:
        if a.mnemonic == "KernelModule":
            action = a
    asserts.true(env, a, "Can't find action with mnemonic KernelModule")

    inputs = sets.make(action.inputs.to_list())
    asserts.true(
        env,
        sets.is_subset(expected_inputs, inputs),
        "Missing inputs to action {}".format(
            sets.to_list(sets.difference(expected_inputs, inputs)),
        ),
    )

    return analysistest.end(env)

_ddk_module_test = analysistest.make(
    impl = _ddk_module_test_impl,
    attrs = {
        "expected_inputs": attr.label_list(allow_files = True),
    },
)

def _ddk_module_test_make(
        name,
        expected_inputs = None,
        **kwargs):
    ddk_module(
        name = name + "_module",
        tags = ["manual"],
        **kwargs
    )

    _ddk_module_test(
        name = name,
        target_under_test = name + "_module",
        expected_inputs = expected_inputs,
    )

def ddk_module_test_suite(name):
    kernel_build(
        name = name + "_kernel_build",
        build_config = "build.config.fake",
        outs = [],
        tags = ["manual"],
    )

    kernel_module(
        name = name + "_legacy_module_a",
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    kernel_module(
        name = name + "_legacy_module_b",
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_self",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_base",
        srcs = ["base.c"],
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_headers(
        name = name + "_headers",
        includes = ["include"],
        hdrs = ["include/subdir.h"],
        tags = ["manual"],
    )

    tests = []

    _ddk_module_test_make(
        name = name + "_simple",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
    )
    tests.append(name + "_simple")

    _ddk_module_test_make(
        name = name + "_dep",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_base"],
    )
    tests.append(name + "_dep")

    _ddk_module_test_make(
        name = name + "_dep2",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_base", name + "_self"],
    )
    tests.append(name + "_dep2")

    _ddk_module_test_make(
        name = name + "_local_headers",
        srcs = ["dep.c", "include/subdir.h"],
        kernel_build = name + "_kernel_build",
        expected_inputs = ["include/subdir.h"],
    )
    tests.append(name + "_local_headers")

    _ddk_module_test_make(
        name = name + "_external_headers",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_headers"],
        expected_inputs = ["include/subdir.h"],
    )
    tests.append(name + "_external_headers")

    _ddk_module_test_make(
        name = name + "_depend_on_legacy_module",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_legacy_module_a"],
    )
    tests.append(name + "_depend_on_legacy_module")

    ddk_module(
        name = name + "_depend_on_legacy_modules_in_the_same_package_module",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_legacy_module_a", name + "_legacy_module_b"],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_depend_on_legacy_modules_in_the_same_package",
        target_under_test = name + "_depend_on_legacy_modules_in_the_same_package_module",
        error_message_substrs = [
            "Conflicting dependencies",
            name + "_legacy_module_a",
            name + "_legacy_module_b",
        ],
    )
    tests.append(name + "_depend_on_legacy_modules_in_the_same_package")

    native.test_suite(
        name = name,
        tests = tests,
    )