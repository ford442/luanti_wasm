// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "catch.h"
#include "catch_amalgamated.hpp"
#include "irrMath.h"
#include "matrix4.h"
#include "irr_v3d.h"
#include "util/numeric.h"
#include <cmath>
#include <functional>

using matrix4 = core::matrix4;

static bool matrix_equals(const matrix4 &a, const matrix4 &b, f32 tolerance = 0.00001f) {
	return a.equals(b, tolerance);
}

constexpr v3f x{1, 0, 0};
constexpr v3f y{0, 1, 0};
constexpr v3f z{0, 0, 1};

constexpr f32 QUARTER_TURN = core::PI / 2;

static void LEFT_HANDED(const std::function<void(core::matrix4 &m, const v3f &rot_rad)> &f) {
	SECTION("rotation is left-handed") {
		SECTION("around the X-axis") {
			matrix4 X;
			f(X, {QUARTER_TURN, 0 , 0});
			CHECK(X.transformVect(x).equals(x));
			CHECK(X.transformVect(y).equals(z));
			CHECK(X.transformVect(z).equals(-y));
		}

		SECTION("around the Y-axis") {
			matrix4 Y;
			f(Y, {0, QUARTER_TURN, 0});
			CHECK(Y.transformVect(y).equals(y));
			CHECK(Y.transformVect(x).equals(-z));
			CHECK(Y.transformVect(z).equals(x));
		}

		SECTION("around the Z-axis") {
			matrix4 Z;
			f(Z, {0, 0, QUARTER_TURN});
			CHECK(Z.transformVect(z).equals(z));
			CHECK(Z.transformVect(x).equals(y));
			CHECK(Z.transformVect(y).equals(-x));
		}
	}
}

TEST_CASE("matrix4") {

// This is in numeric.h rather than matrix4.h, but is conceptually a matrix4 method as well
SECTION("setPitchYawRollRad") {
	SECTION("rotation order is Y*X*Z (matrix notation)") {
		v3f rot{1, 2, 3};
		matrix4 X, Y, Z, YXZ;
		setPitchYawRollRad(X, {rot.X, 0, 0});
		setPitchYawRollRad(Y, {0, rot.Y, 0});
		setPitchYawRollRad(Z, {0, 0, rot.Z});
		setPitchYawRollRad(YXZ, rot);
		CHECK(!matrix_equals(X * Y * Z, YXZ));
		CHECK(!matrix_equals(X * Z * Y, YXZ));
		CHECK(matrix_equals(Y * X * Z, YXZ));
		CHECK(!matrix_equals(Y * Z * X, YXZ));
		CHECK(!matrix_equals(Z * X * Y, YXZ));
		CHECK(!matrix_equals(Z * Y * X, YXZ));
	}

	LEFT_HANDED(setPitchYawRollRad);
}

SECTION("setRotationRadians") {
	SECTION("rotation order is Z*Y*X (matrix notation)") {
		v3f rot{1, 2, 3};
		matrix4 X, Y, Z, ZYX;
		X.setRotationRadians({rot.X, 0, 0});
		Y.setRotationRadians({0, rot.Y, 0});
		Z.setRotationRadians({0, 0, rot.Z});
		ZYX.setRotationRadians(rot);
		CHECK(!matrix_equals(X * Y * Z, ZYX));
		CHECK(!matrix_equals(X * Z * Y, ZYX));
		CHECK(!matrix_equals(Y * X * Z, ZYX));
		CHECK(!matrix_equals(Y * Z * X, ZYX));
		CHECK(!matrix_equals(Z * X * Y, ZYX));
		CHECK(matrix_equals(Z * Y * X, ZYX));
	}

	// See https://en.wikipedia.org/wiki/Right-hand_rule#/media/File:Cartesian_coordinate_system_handedness.svg
	// for a visualization of what handedness means for rotations

	LEFT_HANDED([](core::matrix4 &m, const v3f &rot_rad) {
		m.setRotationRadians(rot_rad);
	});
}

SECTION("getScale") {
	SECTION("correctly gets the length of each row of the 3x3 submatrix") {
		matrix4 A(
			1, 2, 3, 0,
			4, 5, 6, 0,
			7, 8, 9, 0,
			0, 0, 0, 1
		);
		v3f scale = A.getScale();
		CHECK(scale.equals(v3f(
			v3f(1, 2, 3).getLength(),
			v3f(4, 5, 6).getLength(),
			v3f(7, 8, 9).getLength()
		)));
	}
}

SECTION("getRotationRadians") {
	// Test that we can correctly extract a previously set rotation,
	// even after applying a scale, with reasonable precision.
	auto test_rotation_radians = [](v3f rad, v3f scale) {
		matrix4 S;
		S.setScale(scale);
		matrix4 R;
		R.setRotationRadians(rad);
		v3f rot = (R * S).getRotationRadians();
		matrix4 B;
		B.setRotationRadians(rot);
		// Decrease the precision when the angles are close to gimbal lock, as
		// that breaks the expectations of precision with Tait-Bryan angles.
		// Gimbal lock happens when pitch (the angle applied second) is 90 deg
		if (std::abs(std::abs(rot.Y) - QUARTER_TURN) < 0.01f) {
			f32 tol = 0.001f;
			CHECK(matrix_equals(R, B, tol));
		} else {
			CHECK(matrix_equals(R, B));
		}
	};
	SECTION("returns a rotation equivalent to the original rotation") {
		test_rotation_radians({1.0f, 2.0f, 3.0f}, v3f(1));
		// Test cases at or near gimbal lock. These cases fail when using a
		// smaller tolerance.
		test_rotation_radians({1.0f, QUARTER_TURN, 3.0f}, v3f(10.f));
		test_rotation_radians({1.0f, QUARTER_TURN + 0.01001f, 3.0f}, v3f(10.f));
		test_rotation_radians({1.0f, QUARTER_TURN + 0.00999f, 3.0f}, v3f(10.f));
		Catch::Generators::RandomFloatingGenerator<f32> gen_angle(0.0f, 2 * core::PI, Catch::getSeed());
		Catch::Generators::RandomFloatingGenerator<f32> gen_scale(0.1f, 10, Catch::getSeed());
		auto draw = [](auto &gen) {
			f32 f = gen.get();
			gen.next();
			return f;
		};
		auto draw_v3f = [&](auto &gen) {
			return v3f{draw(gen), draw(gen), draw(gen)};
		};
		for (int i = 0; i < 1000; ++i)
			test_rotation_radians(draw_v3f(gen_angle), draw_v3f(gen_scale));
		for (f32 i = 0; i < 4; ++i)
		for (f32 j = 0; j < 4; ++j)
		for (f32 k = 0; k < 4; ++k) {
			v3f rad = core::PI / 4.0f * v3f(i, j, k);
			for (int l = 0; l < 100; ++l) {
				test_rotation_radians(rad, draw_v3f(gen_scale));
			}
		}
	}
}

SECTION("buildCameraLookAtMatrixLH stays orthonormal near pitch ±90") {
	auto check_basis = [](const matrix4 &m) {
		v3f x(m[0], m[4], m[8]);
		v3f y(m[1], m[5], m[9]);
		v3f z(m[2], m[6], m[10]);
		CHECK(x.getLength() == Catch::Approx(1.0f).margin(0.001f));
		CHECK(y.getLength() == Catch::Approx(1.0f).margin(0.001f));
		CHECK(z.getLength() == Catch::Approx(1.0f).margin(0.001f));
		CHECK(std::fabs(x.dotProduct(y)) < 0.002f);
		CHECK(std::fabs(y.dotProduct(z)) < 0.002f);
		CHECK(std::fabs(z.dotProduct(x)) < 0.002f);
	};

	const v3f eye(0.f, 10.f, 0.f);
	const v3f world_up(0.f, 1.f, 0.f);
	for (f32 pitch_deg : {-90.f, -85.f, -70.f, 70.f, 85.f, 90.f}) {
		const f32 pitch = pitch_deg * core::DEGTORAD;
		v3f target = eye + v3f(0.f, std::sin(pitch), std::cos(pitch));
		matrix4 m;
		m.buildCameraLookAtMatrixLH(eye, target, world_up);
		check_basis(m);
	}
}

}
