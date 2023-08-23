
/* temporary math function classes until the API has them */

/* tilman helper functions start */
const float EPS = 0.0000099999997f;
const float EPS2 = 9.9999994e-11f /*EPS * EPS*/;

GmVec3 Cross(const GmVec3&in a, const GmVec3&in b) {
    GmVec3 result;
    result.x = a.y * b.z - a.z * b.y;
    result.y = a.z * b.x - a.x * b.z;
    result.z = a.x * b.y - a.y * b.x;
    return result;
}

float Dot(const GmVec3&in a, const GmVec3&in b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

float Norm2(const GmVec3&in a) {
    return Dot(a, a);
}

float Norm(const GmVec3&in a) {
    return Math::Sqrt(Dot(a, a));
}

GmVec3 SafeNormalize(GmVec3 a) {
    const float N2 = Norm2(a);
    if (EPS2 < Norm2(a)) {
        a /= Math::Sqrt(N2);
    }
    return a;
}
/* tilman helper functions end */



class GmVec3 {
    float x;
    float y;
    float z;
    
    GmVec3() {}
    GmVec3(float num) {
        this.x = num;
        this.y = num;
        this.z = num;
    }
    GmVec3(float x, float y, float z) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    GmVec3(const GmVec3&in other) {
        this.x = other.x;
        this.y = other.y;
        this.z = other.z;
    }
    GmVec3(const vec3&in other) {
        this.x = other.x;
        this.y = other.y;
        this.z = other.z;
    }

    void Mult(const GmMat3&in other) {
        float _x = x * other.x.x + y * other.x.y + z * other.x.z;
        float _y = x * other.y.x + y * other.y.y + z * other.y.z;
        z = x * other.z.x + y * other.z.y + z * other.z.z;
        x = _x;
        y = _y;
    }

    void Mult(const GmIso4&in other) {
        float _x = x * other.m_Rotation.x.x + y * other.m_Rotation.x.y + z * other.m_Rotation.x.z + other.m_Position.x;
        float _y = x * other.m_Rotation.y.x + y * other.m_Rotation.y.y + z * other.m_Rotation.y.z + other.m_Position.y;
        z = x * other.m_Rotation.z.x + y * other.m_Rotation.z.y + z * other.m_Rotation.z.z + other.m_Position.z;
        x = _x;
        y = _y;
    }

    void MultTranspose(const GmMat3&in other) {
        float _x = x * other.x.x + y * other.y.x + z * other.z.x;
        float _y = x * other.x.y + y * other.y.y + z * other.z.y;
        z = x * other.x.z + y * other.y.z + z * other.z.z;
        x = _x;
        y = _y;
    }

    void SetMult(const GmVec3&in arg0, const GmIso4&in arg1) {
        x = arg1.m_Rotation.x.x * arg0.x + arg1.m_Rotation.x.y * arg0.y + arg1.m_Rotation.x.z * arg0.z + arg1.m_Position.x;
        y = arg1.m_Rotation.y.x * arg0.x + arg1.m_Rotation.y.y * arg0.y + arg1.m_Rotation.y.z * arg0.z + arg1.m_Position.y;
        z = arg1.m_Rotation.z.x * arg0.x + arg1.m_Rotation.z.y * arg0.y + arg1.m_Rotation.z.z * arg0.z + arg1.m_Position.z;
    }

    string dump {
        get const {
            return "GmVec3(" + x + ", " + y + ", " + z + ")";
        }
    }

    GmVec3 opAdd(const GmVec3&in other) {
        GmVec3 result;
        result.x = x + other.x;
        result.y = y + other.y;
        result.z = z + other.z;
        return result;
    }

    GmVec3 opSub(const GmVec3&in other) {
        GmVec3 result;
        result.x = x - other.x;
        result.y = y - other.y;
        result.z = z - other.z;
        return result;
    }

    GmVec3 opMul(const float&in other) {
        GmVec3 result;
        result.x = x * other;
        result.y = y * other;
        result.z = z * other;
        return result;
    }

    GmVec3 opDiv(const float&in other) {
        GmVec3 result;
        result.x = x / other;
        result.y = y / other;
        result.z = z / other;
        return result;
    }

    GmVec3 opDiv(const GmVec3&in other) {
        GmVec3 result;
        result.x = x / other.x;
        result.y = y / other.y;
        result.z = z / other.z;
        return result;
    }

    void opAddAssign(const GmVec3&in other) {
        x += other.x;
        y += other.y;
        z += other.z;
    }

    void opSubAssign(const GmVec3&in other) {
        x -= other.x;
        y -= other.y;
        z -= other.z;
    }

    void opMulAssign(const float&in other) {
        x *= other;
        y *= other;
        z *= other;
    }

    void opMulAssign(const GmVec3&in other) {
        x *= other.x;
        y *= other.y;
        z *= other.z;
    }

    void opDivAssign(const float&in other) {
        x /= other;
        y /= other;
        z /= other;
    }

    void opDivAssign(const GmVec3&in other) {
        x /= other.x;
        y /= other.y;
        z /= other.z;
    }
}

class GmMat3 {
    GmVec3 x(1.0f, 0.0f, 0.0f);
    GmVec3 y(0.0f, 1.0f, 0.0f);
    GmVec3 z(0.0f, 0.0f, 1.0f);

    GmMat3() {}
    GmMat3(const GmMat3&in other) {
        this.x = other.x;
        this.y = other.y;
        this.z = other.z;
    }
    GmMat3(const GmVec3&in x, const GmVec3&in y, const GmVec3&in z) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    GmMat3(const mat3&in other) {
        this.x = GmVec3(other.x);
        this.y = GmVec3(other.y);
        this.z = GmVec3(other.z);
    }

    void SetIdentity() {
        this.x.x = 1.0f;
        this.x.y = 0.0f;
        this.x.z = 0.0f;
        this.y.x = 0.0f;
        this.y.y = 1.0f;
        this.y.z = 0.0f;
        this.z.x = 0.0f;
        this.z.y = 0.0f;
        this.z.z = 1.0f;
    }

    void Mult(const GmMat3&in other) {
        float _xx = x.x * other.x.x + y.x * other.x.y + z.x * other.x.z;
        float _xy = x.y * other.x.x + y.y * other.x.y + z.y * other.x.z;
        float _xz = x.z * other.x.x + y.z * other.x.y + z.z * other.x.z;
        float _yx = x.x * other.y.x + y.x * other.y.y + z.x * other.y.z;
        float _yy = x.y * other.y.x + y.y * other.y.y + z.y * other.y.z;
        float _yz = x.z * other.y.x + y.z * other.y.y + z.z * other.y.z;
        z.x = x.x * other.z.x + y.x * other.z.y + z.x * other.z.z;
        z.y = x.y * other.z.x + y.y * other.z.y + z.y * other.z.z;
        z.z = x.z * other.z.x + y.z * other.z.y + z.z * other.z.z;
        x.x = _xx;
        x.y = _xy;
        x.z = _xz;
        y.x = _yx;
        y.y = _yy;
        y.z = _yz;
    }

    void MultTranspose(const GmMat3&in other) {
        float _xx = x.x * other.x.x + y.x * other.y.x + z.x * other.z.x;
        float _xy = x.y * other.x.x + y.y * other.y.x + z.y * other.z.x;
        float _xz = x.z * other.x.x + y.z * other.y.x + z.z * other.z.x;
        float _yx = x.x * other.x.y + y.x * other.y.y + z.x * other.z.y;
        float _yy = x.y * other.x.y + y.y * other.y.y + z.y * other.z.y;
        float _yz = x.z * other.x.y + y.z * other.y.y + z.z * other.z.y;
        z.x = x.x * other.x.z + y.x * other.y.z + z.x * other.z.z;
        z.y = x.y * other.x.z + y.y * other.y.z + z.y * other.z.z;
        z.z = x.z * other.x.z + y.z * other.y.z + z.z * other.z.z;
        x.x = _xx;
        x.y = _xy;
        x.z = _xz;
        y.x = _yx;
        y.y = _yy;
        y.z = _yz;
    }

    void RotateX(float rad) {
        float sin_pos = Math::Sin(rad);
        float sin_neg = -sin_pos;
        float cos_pos = Math::Cos(rad);

        GmVec3 y_temp(y);

        y.x = y.x * cos_pos + z.x * sin_neg;
        y.y = y.y * cos_pos + z.y * sin_neg;
        y.z = y.z * cos_pos + z.z * sin_neg;
        z.x = z.x * cos_pos + y_temp.x * sin_pos;
        z.y = z.y * cos_pos + y_temp.y * sin_pos;
        z.z = z.z * cos_pos + y_temp.z * sin_pos;
    }

    void RotateY(float rad) {
        float sin_pos = Math::Sin(rad);
        float sin_neg = -sin_pos;
        float cos_pos = Math::Cos(rad);

        GmVec3 x_temp(x);

        x.x = x.x * cos_pos + z.x * sin_pos;
        x.y = x.y * cos_pos + z.y * sin_pos;
        x.z = x.z * cos_pos + z.z * sin_pos;
        z.x = z.x * cos_pos + x_temp.x * sin_neg;
        z.y = z.y * cos_pos + x_temp.y * sin_neg;
        z.z = z.z * cos_pos + x_temp.z * sin_neg;
    }

    void RotateZ(float rad) {
        float sin_pos = Math::Sin(rad);
        float sin_neg = -sin_pos;
        float cos_pos = Math::Cos(rad);

        GmVec3 x_temp(x);

        x.x = x.x * cos_pos + y.x * sin_neg;
        x.y = x.y * cos_pos + y.y * sin_neg;
        x.z = x.z * cos_pos + y.z * sin_neg;
        y.x = y.x * cos_pos + x_temp.x * sin_pos;
        y.y = y.y * cos_pos + x_temp.y * sin_pos;
        y.z = y.z * cos_pos + x_temp.z * sin_pos;
    }

    // operator overloads
    GmMat3 opAdd(const GmMat3&in other) {
        GmMat3 result;
        result.x = x + other.x;
        result.y = y + other.y;
        result.z = z + other.z;
        return result;
    }

    GmMat3 opSub(const GmMat3&in other) {
        GmMat3 result;
        result.x = x - other.x;
        result.y = y - other.y;
        result.z = z - other.z;
        return result;
    }

    GmMat3 opMul(const float&in other) {
        GmMat3 result;
        result.x = x * other;
        result.y = y * other;
        result.z = z * other;
        return result;
    }

    GmMat3 opMul(const GmMat3&in other) {
        GmMat3 result;
        result.x = x * other.x.x + y * other.x.y + z * other.x.z;
        result.y = x * other.y.x + y * other.y.y + z * other.y.z;
        result.z = x * other.z.x + y * other.z.y + z * other.z.z;
        return result;
    }

    GmVec3 opMul(const GmVec3&in other) {
        GmVec3 result;
        result.x = x.x * other.x + y.x * other.y + z.x * other.z;
        result.y = x.y * other.x + y.y * other.y + z.y * other.z;
        result.z = x.z * other.x + y.z * other.y + z.z * other.z;
        return result;
    }

    void opAddAssign(const GmMat3&in other) {
        x += other.x;
        y += other.y;
        z += other.z;
    }

    void opSubAssign(const GmMat3&in other) {
        x -= other.x;
        y -= other.y;
        z -= other.z;
    }

    void opMulAssign(const float&in other) {
        x *= other;
        y *= other;
        z *= other;
    }

    void opMulAssign(const GmMat3&in other) {
        float _xx = x.x * other.x.x + y.x * other.x.y + z.x * other.x.z;
        float _xy = x.y * other.x.x + y.y * other.x.y + z.y * other.x.z;
        float _xz = x.z * other.x.x + y.z * other.x.y + z.z * other.x.z;
        float _yx = x.x * other.y.x + y.x * other.y.y + z.x * other.y.z;
        float _yy = x.y * other.y.x + y.y * other.y.y + z.y * other.y.z;
        float _yz = x.z * other.y.x + y.z * other.y.y + z.z * other.y.z;
        z.x = x.x * other.z.x + y.x * other.z.y + z.x * other.z.z;
        z.y = x.y * other.z.x + y.y * other.z.y + z.y * other.z.z;
        z.z = x.z * other.z.x + y.z * other.z.y + z.z * other.z.z;
        x.x = _xx;
        x.y = _xy;
        x.z = _xz;
        y.x = _yx;
        y.y = _yy;
        y.z = _yz;
    }

    void opMulAssign(const GmVec3&in other) {
        float _x = x.x * other.x + y.x * other.y + z.x * other.z;
        float _y = x.y * other.x + y.y * other.y + z.y * other.z;
        z.z = x.z * other.x + y.z * other.y + z.z * other.z;
        x.x = _x;
        x.y = _y;
    }

    void opDivAssign(const float&in other) {
        x /= other;
        y /= other;
        z /= other;
    }

    void opDivAssign(const GmMat3&in other) {
        float _xx = x.x * other.x.x + y.x * other.x.y + z.x * other.x.z;
        float _xy = x.y * other.x.x + y.y * other.x.y + z.y * other.x.z;
        float _xz = x.z * other.x.x + y.z * other.x.y + z.z * other.x.z;
        float _yx = x.x * other.y.x + y.x * other.y.y + z.x * other.y.z;
        float _yy = x.y * other.y.x + y.y * other.y.y + z.y * other.y.z;
        float _yz = x.z * other.y.x + y.z * other.y.y + z.z * other.y.z;
        z.x = x.x * other.z.x + y.x * other.z.y + z.x * other.z.z;
        z.y = x.y * other.z.x + y.y * other.z.y + z.y * other.z.z;
        z.z = x.z * other.z.x + y.z * other.z.y + z.z * other.z.z;
        x.x = _xx;
        x.y = _xy;
        x.z = _xz;
        y.x = _yx;
        y.y = _yy;
        y.z = _yz;
    }

    void opDivAssign(const GmVec3&in other) {
        float _x = x.x * other.x + y.x * other.y + z.x * other.z;
        float _y = x.y * other.x + y.y * other.y + z.y * other.z;
        z.z = x.z * other.x + y.z * other.y + z.z * other.z;
        x.x = _x;
        x.y = _y;
    }

    string dump {
        get const {
            return "GmMat3(" + x.x + ", " + x.y + ", " + x.z + ", " + y.x + ", " + y.y + ", " + y.z + ", " + z.x + ", " + z.y + ", " + z.z + ")";
        }
    }
}

class GmIso4 {
    GmMat3 m_Rotation;
    GmVec3 m_Position;

    GmIso4() {}
    GmIso4(const GmIso4&in other) {
        this.m_Rotation = other.m_Rotation;
        this.m_Position = other.m_Position;
    }
    GmIso4(const GmMat3&in rotation, const GmVec3&in position) {
        this.m_Rotation = rotation;
        this.m_Position = position;
    }
    GmIso4(const iso4&in other) {
        this.m_Rotation = GmMat3(other.Rotation);
        this.m_Position = GmVec3(other.Position);
    }
    GmIso4(const mat3&in rotation, const vec3&in position) {
        this.m_Rotation = GmMat3(rotation);
        this.m_Position = GmVec3(position);
    }

    void SetIdentity() {
        m_Rotation.SetIdentity();
        m_Position.x = 0.0f;
        m_Position.y = 0.0f;
        m_Position.z = 0.0f;
    }

    void Mult(const GmIso4&in other) {
        m_Rotation.Mult(other.m_Rotation);
        m_Position.Mult(other);
    }

    void MultInverse(const GmIso4&in other) {
        m_Position.MultTranspose(other.m_Rotation);
        m_Position -= other.m_Position;
        m_Rotation.MultTranspose(other.m_Rotation);
    }

    void SetInverse(const GmIso4&in other) {
        m_Rotation.x.x = other.m_Rotation.x.x;
        m_Rotation.y.y = other.m_Rotation.y.y;
        m_Rotation.z.z = other.m_Rotation.z.z;
        m_Rotation.x.y = other.m_Rotation.y.x;
        m_Rotation.y.x = other.m_Rotation.x.y;
        m_Rotation.x.z = other.m_Rotation.z.x;
        m_Rotation.z.x = other.m_Rotation.x.z;
        m_Rotation.y.z = other.m_Rotation.z.y;
        m_Rotation.z.y = other.m_Rotation.y.z;
        m_Position.x = -other.m_Position.x;
        m_Position.y = -other.m_Position.y;
        m_Position.z = -other.m_Position.z;
        m_Position.Mult(m_Rotation);
    }

    void RotateX(float rad) {
        m_Rotation.RotateX(rad);
    }

    void RotateY(float rad) {
        m_Rotation.RotateY(rad);
    }

    void RotateZ(float rad) {
        m_Rotation.RotateZ(rad);
    }

    string dump {
        get const {
            return "GmIso4(" + m_Rotation.x.x + ", " + m_Rotation.x.y + ", " + m_Rotation.x.z + ", " + m_Rotation.y.x + ", " + m_Rotation.y.y + ", " + m_Rotation.y.z + ", " + m_Rotation.z.x + ", " + m_Rotation.z.y + ", " + m_Rotation.z.z + ", " + m_Position.x + ", " + m_Position.y + ", " + m_Position.z + ")";
        }
    }
}

enum EGmSurfType {
    GmSurfType_Sphere,
    GmSurfType_Ellipsoid,
    GmSurfType_Plane,
    GmSurfType_QuadHeight,
    GmSurfType_TriangleHeight,
    GmSurfType_Polygon,
    GmSurfType_Box,
    GmSurfType_Mesh,
    GmSurfType_Cylinder,
    GmSurfType_Count
};

class GmSurf {
    TM::PlugSurfaceMaterialId m_MaterialId;
    EGmSurfType m_GmSurfType;
}

class GmSurfEllipsoid : GmSurf {
    GmVec3 m_SemiAxis;
}

class STriangle {
    STriangle() {
        m_VertexIndices.Resize(3);
    }
    GmVec3 m_Normal;
    float m_Distance;
    array<uint> m_VertexIndices;
    TM::PlugSurfaceMaterialId m_MaterialId;
}


class GmSurfMesh : GmSurf {
    array<GmVec3> m_Vertices;
    array<STriangle> m_Triangles;
    array<uint> field_0x18;
    // GmOctree m_Octree;
}