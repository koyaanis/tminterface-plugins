// this helper class solely for the purpose of optimizations, used for collision detection inside IsColliding()
TriggerMesh@ __triggerMesh = TriggerMesh(); // singleton
class TriggerMesh {
    GmSurfMesh@ mesh = @GmSurfMesh();

    // all of the variables below are simply helper variables / variables that hold information
    // that we do not wish to calculate over and over again
    
    // the trigger that the mesh is for
    Trigger3D trigger;
    
    // 4x3 matrix for the mesh
    GmIso4 m_Location;

    // helper var, i do not wish to re-allocate / set the size of this over and over again
    array<GmVec3> vertices;

    array<GmVec3> ellipsoidDimensions;
    array<GmVec3> ellipsoidDimensionsInverse;

    // bounding box collision check helper vars
    float bbCheckXNegative;
    float bbCheckXPositive;
    float bbCheckYNegative;
    float bbCheckYPositive;
    float bbCheckZNegative;
    float bbCheckZPositive;
    
    TriggerMesh() {
        if (@__triggerMesh != null) {
            print("TriggerMesh is a singleton class");
        }

        @__triggerMesh = @this;

        this.vertices.Resize(3);

        // this isnt really used anymore other than below where i set the inverse, but its still good to have somewhere
        this.ellipsoidDimensions.Resize(8);
        this.ellipsoidDimensions[0] = GmVec3(0.182f, 0.364f, 0.364f);
        this.ellipsoidDimensions[1] = GmVec3(0.182f, 0.364f, 0.364f);
        this.ellipsoidDimensions[2] = GmVec3(0.182f, 0.364f, 0.364f);
        this.ellipsoidDimensions[3] = GmVec3(0.182f, 0.364f, 0.364f);
        this.ellipsoidDimensions[4] = GmVec3(0.439118f, 0.362f, 1.901528f);
        this.ellipsoidDimensions[5] = GmVec3(0.968297f, 0.362741f, 1.682276f);
        this.ellipsoidDimensions[6] = GmVec3(1.020922f, 0.515218f, 1.038007f);
        this.ellipsoidDimensions[7] = GmVec3(0.384841f, 0.905323f, 0.283418f);

        this.ellipsoidDimensionsInverse.Resize(8);
        this.ellipsoidDimensionsInverse[0] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[0];
        this.ellipsoidDimensionsInverse[1] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[1];
        this.ellipsoidDimensionsInverse[2] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[2];
        this.ellipsoidDimensionsInverse[3] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[3];
        this.ellipsoidDimensionsInverse[4] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[4];
        this.ellipsoidDimensionsInverse[5] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[5];
        this.ellipsoidDimensionsInverse[6] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[6];
        this.ellipsoidDimensionsInverse[7] = GmVec3(1.0, 1.0, 1.0) / this.ellipsoidDimensions[7];
    }

    TriggerMesh@ CreateOrGetTriggerMesh(const Trigger3D&in trigger) {
        if (trigger.Position == this.trigger.Position && trigger.Size == this.trigger.Size) {
            return @__triggerMesh;
        } else {
            @this.mesh = @GmSurfMesh();
        }

        // set trigger
        this.trigger = trigger;

        // set the iso4 location of the mesh (trigger has no rotation atm so we leave it identity)
        this.m_Location.m_Position = GmVec3(this.trigger.Position);

        // set bounding box collision check helper vars
        float longestDistanceCarMiddleToCorner = 2.36994570359f; // not to be confused with car position
        this.bbCheckXNegative = this.trigger.Position.x - longestDistanceCarMiddleToCorner;
        this.bbCheckXPositive = this.trigger.Position.x + trigger.Size.x + longestDistanceCarMiddleToCorner;
        this.bbCheckYNegative = this.trigger.Position.y - longestDistanceCarMiddleToCorner;
        this.bbCheckYPositive = this.trigger.Position.y + trigger.Size.y + longestDistanceCarMiddleToCorner;
        this.bbCheckZNegative = this.trigger.Position.z - longestDistanceCarMiddleToCorner;
        this.bbCheckZPositive = this.trigger.Position.z + trigger.Size.z + longestDistanceCarMiddleToCorner;
        

        // trigger bottom
        this.mesh.m_Vertices.Add(GmVec3(0.0f, 0.0f, 0.0f));
        this.mesh.m_Vertices.Add(GmVec3(0.0f, 0.0f, trigger.Size.z));
        this.mesh.m_Vertices.Add(GmVec3(trigger.Size.x, 0.0f, trigger.Size.z));
        this.mesh.m_Vertices.Add(GmVec3(trigger.Size.x, 0.0f, 0.0f));
        // trigger top
        this.mesh.m_Vertices.Add(GmVec3(0.0f, trigger.Size.y, 0.0f));
        this.mesh.m_Vertices.Add(GmVec3(0.0f, trigger.Size.y, trigger.Size.z));
        this.mesh.m_Vertices.Add(GmVec3(trigger.Size.x, trigger.Size.y, trigger.Size.z));
        this.mesh.m_Vertices.Add(GmVec3(trigger.Size.x, trigger.Size.y, 0.0f));

        this.mesh.m_Triangles.Resize(12);
        // bottom
        this.mesh.m_Triangles[0].m_VertexIndices[0] = 0;
        this.mesh.m_Triangles[0].m_VertexIndices[1] = 1;
        this.mesh.m_Triangles[0].m_VertexIndices[2] = 2;
        this.mesh.m_Triangles[0].m_Normal = GmVec3(0.0f, 1.0f, 0.0f);
        this.mesh.m_Triangles[0].m_Distance = 0.0f;
        this.mesh.m_Triangles[0].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[1].m_VertexIndices[0] = 2;
        this.mesh.m_Triangles[1].m_VertexIndices[1] = 3;
        this.mesh.m_Triangles[1].m_VertexIndices[2] = 0;
        this.mesh.m_Triangles[1].m_Normal = GmVec3(0.0f, 1.0f, 0.0f);
        this.mesh.m_Triangles[1].m_Distance = 0.0f;
        this.mesh.m_Triangles[1].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        // top
        this.mesh.m_Triangles[2].m_VertexIndices[0] = 4;
        this.mesh.m_Triangles[2].m_VertexIndices[1] = 5;
        this.mesh.m_Triangles[2].m_VertexIndices[2] = 6;
        this.mesh.m_Triangles[2].m_Normal = GmVec3(0.0f, -1.0f, 0.0f);
        this.mesh.m_Triangles[2].m_Distance = trigger.Size.y;
        this.mesh.m_Triangles[2].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[3].m_VertexIndices[0] = 6;
        this.mesh.m_Triangles[3].m_VertexIndices[1] = 7;
        this.mesh.m_Triangles[3].m_VertexIndices[2] = 4;
        this.mesh.m_Triangles[3].m_Normal = GmVec3(0.0f, -1.0f, 0.0f);
        this.mesh.m_Triangles[3].m_Distance = trigger.Size.y;
        this.mesh.m_Triangles[3].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        // front
        this.mesh.m_Triangles[4].m_VertexIndices[0] = 0;
        this.mesh.m_Triangles[4].m_VertexIndices[1] = 1;
        this.mesh.m_Triangles[4].m_VertexIndices[2] = 5;
        this.mesh.m_Triangles[4].m_Normal = GmVec3(1.0f, 0.0f, 0.0f);
        this.mesh.m_Triangles[4].m_Distance = 0.0f;
        this.mesh.m_Triangles[4].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[5].m_VertexIndices[0] = 5;
        this.mesh.m_Triangles[5].m_VertexIndices[1] = 4;
        this.mesh.m_Triangles[5].m_VertexIndices[2] = 0;
        this.mesh.m_Triangles[5].m_Normal = GmVec3(1.0f, 0.0f, 0.0f);
        this.mesh.m_Triangles[5].m_Distance = 0.0f;
        this.mesh.m_Triangles[5].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        // back
        this.mesh.m_Triangles[6].m_VertexIndices[0] = 2;
        this.mesh.m_Triangles[6].m_VertexIndices[1] = 3;
        this.mesh.m_Triangles[6].m_VertexIndices[2] = 7;
        this.mesh.m_Triangles[6].m_Normal = GmVec3(-1.0f, 0.0f, 0.0f);
        this.mesh.m_Triangles[6].m_Distance = trigger.Size.x;
        this.mesh.m_Triangles[6].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[7].m_VertexIndices[0] = 7;
        this.mesh.m_Triangles[7].m_VertexIndices[1] = 6;
        this.mesh.m_Triangles[7].m_VertexIndices[2] = 2;
        this.mesh.m_Triangles[7].m_Normal = GmVec3(-1.0f, 0.0f, 0.0f);
        this.mesh.m_Triangles[7].m_Distance = trigger.Size.x;
        this.mesh.m_Triangles[7].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        // left
        this.mesh.m_Triangles[8].m_VertexIndices[0] = 3;
        this.mesh.m_Triangles[8].m_VertexIndices[1] = 0;
        this.mesh.m_Triangles[8].m_VertexIndices[2] = 4;
        this.mesh.m_Triangles[8].m_Normal = GmVec3(0.0f, 0.0f, 1.0f);
        this.mesh.m_Triangles[8].m_Distance = 0.0f;
        this.mesh.m_Triangles[8].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[9].m_VertexIndices[0] = 4;
        this.mesh.m_Triangles[9].m_VertexIndices[1] = 7;
        this.mesh.m_Triangles[9].m_VertexIndices[2] = 3;
        this.mesh.m_Triangles[9].m_Normal = GmVec3(0.0f, 0.0f, 1.0f);
        this.mesh.m_Triangles[9].m_Distance = 0.0f;
        this.mesh.m_Triangles[9].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        // right
        this.mesh.m_Triangles[10].m_VertexIndices[0] = 1;
        this.mesh.m_Triangles[10].m_VertexIndices[1] = 2;
        this.mesh.m_Triangles[10].m_VertexIndices[2] = 6;
        this.mesh.m_Triangles[10].m_Normal = GmVec3(0.0f, 0.0f, -1.0f);
        this.mesh.m_Triangles[10].m_Distance = 0.0f;
        this.mesh.m_Triangles[10].m_MaterialId = TM::PlugSurfaceMaterialId(0);
        this.mesh.m_Triangles[11].m_VertexIndices[0] = 6;
        this.mesh.m_Triangles[11].m_VertexIndices[1] = 5;
        this.mesh.m_Triangles[11].m_VertexIndices[2] = 1;
        this.mesh.m_Triangles[11].m_Normal = GmVec3(0.0f, 0.0f, -1.0f);
        this.mesh.m_Triangles[11].m_Distance = 0.0f;
        this.mesh.m_Triangles[11].m_MaterialId = TM::PlugSurfaceMaterialId(0);

        return @__triggerMesh;
    }
    
    void GetCarEllipsoidLocationByIndex(SimulationManager@ simManager, const GmIso4&in carLocation, uint index, GmIso4&out location) {
        switch(index) {
            case 0:
            {
                location.m_Position = simManager.Wheels.FrontLeft.SurfaceHandler.Location.Position;
                location.Mult(carLocation);
                break;
            }
            // wheel 1-3 is calculated manually because theres a bug and only FrontLeft is given back.
            // the data is not correct since i only use the damperval of front left
            case 1:
            {
                float damperAbsorbValue = simManager.Wheels.FrontLeft.RTState.DamperAbsorbVal;
                GmVec3 translationFromCar(-0.863012f, 0.3525f, 1.782089f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                location.m_Position.y -= damperAbsorbValue;
                break;
            }
            case 2:
            {
                float damperAbsorbValue = simManager.Wheels.FrontLeft.RTState.DamperAbsorbVal;
                GmVec3 translationFromCar(0.885002f, 0.352504f, -1.205502f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                location.m_Position.y -= damperAbsorbValue;
                break;
            }
            case 3:
            {
                float damperAbsorbValue = simManager.Wheels.FrontLeft.RTState.DamperAbsorbVal;
                GmVec3 translationFromCar(-0.885002f, 0.352504f, -1.205502f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                location.m_Position.y -= damperAbsorbValue;
                break;
            }
            case 4:
            {
                // bodysurf1
                GmVec3 translationFromCar(0.0f, 0.471253f, 0.219106f);
                // in the data this pitch was negative, somehow i had to make it positive to get the correct result
                float pitch = 3.4160502f;
                // Math::ToRad(3.4160502f); -> 0.0596213234033 (pitch)
                location.m_Rotation.RotateX(0.0596213234033f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                break;
            }
            case 5:
            {
                // bodysurf2
                GmVec3 translationFromCar(0.0f, 0.448782f, -0.20792f);
                // in the data this pitch was negative, somehow i had to make it positive to get the correct result
                // float pitch = 2.6202483f -> 0.0457319600547 (pitch)
                location.m_Rotation.RotateX(0.0457319600547f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                break;
            }
            case 6:
            {
                // bodysurf3
                GmVec3 translationFromCar(0.0f, 0.652812f, -0.89763f);
                // in the data this pitch was negative, somehow i had to make it positive to get the correct result
                // float pitch = 2.6874702f;
                // Math::ToRad(2.6874702f); -> 0.0469052035391 (pitch)
                location.m_Rotation.RotateX(0.0469052035391f);
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                break;
            }
            case 7:
            {
                // bodysurf4
                GmVec3 translationFromCar(-0.015532f, 0.363252f, 1.75357f);
                // float pitch = 0.0f;
                // float yaw = 90.0f;
                //float roll = -180.0f;
                // for some reason, the data said pitch 0 but i ended up having to use 90, and roll doesnt really seem to matter? this needs to be looked into
                // Math::ToRad(90.0f); -> 1.5708 (pitch, despite above / data saying 0.0)
                location.m_Rotation.RotateX(1.5708f);
                // Math::ToRad(90.0); -> 1.5708 (yaw)
                location.m_Rotation.RotateY(1.5708f);
                // not used?
                //location.m_Rotation.RotateZ(Math::ToRad(roll));
                location.Mult(carLocation);
                translationFromCar.Mult(carLocation.m_Rotation);
                location.m_Position += translationFromCar;
                break;
            }
        }
    }
}


bool IsColliding(SimulationManager@ simManager, const Trigger3D&in trigger) {
    TriggerMesh@ triggerMesh = @__triggerMesh.CreateOrGetTriggerMesh(trigger);

    // simple bounding box check, before doing heavy calculations
    const float carMiddleX = simManager.Dyna.CurrentState.Location.Position.x;
    if (carMiddleX < triggerMesh.bbCheckXNegative || carMiddleX > triggerMesh.bbCheckXPositive) {
        return false;
    }

    const float carMiddleZ = 0.578265f * simManager.Dyna.CurrentState.Location.Rotation.z.y + 0.113769f * simManager.Dyna.CurrentState.Location.Rotation.z.z + simManager.Dyna.CurrentState.Location.Position.z;
    if (carMiddleZ < triggerMesh.bbCheckZNegative || carMiddleZ > triggerMesh.bbCheckZPositive) {
        return false;
    }

    const float carMiddleY = 0.578265f * simManager.Dyna.CurrentState.Location.Rotation.y.y + 0.113769f * simManager.Dyna.CurrentState.Location.Rotation.y.z + simManager.Dyna.CurrentState.Location.Position.y;
    if (carMiddleY < triggerMesh.bbCheckYNegative || carMiddleY > triggerMesh.bbCheckYPositive) {
        return false;
    }

    /* code below was reversed engineered from the original game by me + tilman. big thanks for tilman for giving the variables better names, he knows the maths better than me */
    const GmIso4@ carLocation = simManager.Dyna.CurrentState.Location;

    bool gotAnyCollision = false;

    // take some vars out of loop for performance
    GmIso4 ellipsoidLocation;
    GmIso4 meshToEllipseTransform;
    for (uint ellipsoidId = 0; ellipsoidId < 8; ellipsoidId++) {
        triggerMesh.GetCarEllipsoidLocationByIndex(simManager, carLocation, ellipsoidId, ellipsoidLocation);
        const GmVec3@ ellipsoidDimensionsInverse = triggerMesh.ellipsoidDimensionsInverse[ellipsoidId];

        ellipsoidLocation.MultInverse(triggerMesh.m_Location);
        
        meshToEllipseTransform.SetInverse(ellipsoidLocation);
        meshToEllipseTransform.m_Rotation.x *= ellipsoidDimensionsInverse.x;
        meshToEllipseTransform.m_Rotation.y *= ellipsoidDimensionsInverse.y;
        meshToEllipseTransform.m_Rotation.z *= ellipsoidDimensionsInverse.z;
        meshToEllipseTransform.m_Position *= ellipsoidDimensionsInverse;

        for (uint triangleId = 0; triangleId < triggerMesh.mesh.m_Triangles.Length; triangleId++) {
            const STriangle@ triangle = @triggerMesh.mesh.m_Triangles[triangleId];

            triggerMesh.vertices[0].SetMult(triggerMesh.mesh.m_Vertices[triangle.m_VertexIndices[0]], meshToEllipseTransform);
            triggerMesh.vertices[1].SetMult(triggerMesh.mesh.m_Vertices[triangle.m_VertexIndices[1]], meshToEllipseTransform);
            triggerMesh.vertices[2].SetMult(triggerMesh.mesh.m_Vertices[triangle.m_VertexIndices[2]], meshToEllipseTransform);

            GmVec3 triNormal = Cross(triggerMesh.vertices[1] - triggerMesh.vertices[0], triggerMesh.vertices[2] - triggerMesh.vertices[0]);
            const float triNormalN2 = Norm2(triNormal);
            if (triNormalN2 <= EPS2) {
                continue;
            }
            triNormal *= 1.0f / Math::Sqrt(triNormalN2);

            const float distance = Dot(GmVec3(0, 0, 0) - triggerMesh.vertices[0], triNormal);

            // this has lead to only half of the collisions being detected.
            // it seems that d needs to be in the range [-1, 1] for the collision to be detected.
            // if (d < 0.0f || d > 1.0f) {
            if (distance < -1.0f || distance > 1.0f) {
                continue;
            }

            const float ds = Math::Sqrt(1.0f - distance * distance);
            GmVec3@ intersectionPoint = triNormal * -distance;

            for (int i = 0; i < 3; i++) {
                GmVec3@ vA = triggerMesh.vertices[i];
                GmVec3@ vB = triggerMesh.vertices[i == 2 ? 0 : i + 1];
                GmVec3 edge = vB - vA;
                const float edgeN2 = Norm2(edge);
                if (edgeN2 > EPS2) {
                    edge *= 1.0f / Math::Sqrt(edgeN2);
                }
                GmVec3@ a = Cross(edge, triNormal);
                GmVec3@ b = intersectionPoint - vA;
                const float d2 = Dot(a, b);
                if (ds < d2) {
                    break;
                }
                if (d2 > 0) {
                    const float d3 = Dot(b, edge);
                    if (d3 >= 0.0f) {
                        const GmVec3 c = intersectionPoint - vB;
                        const float d4 = Dot(c, edge);
                        if (d4 <= 0.0f) {
                            const GmVec3 point = intersectionPoint + a * (-d2);
                            const float normalN2 = Norm2(GmVec3(0, 0, 0) - point);
                            if (normalN2 <= EPS) {
                                break;
                            }

                            return true;
                        } else {
                            const float normalN2 = Norm(GmVec3(0, 0, 0) - vB);
                            if (normalN2 > 1.0f || normalN2 <= EPS2) {
                                break;
                            }

                            return true;
                        }
                    } else {
                        const float normalN2 = Norm2(GmVec3(0, 0, 0) - vA);
                        if (normalN2 > 1.0f || normalN2 <= EPS2) {
                            break;
                        }

                        return true;
                    }
                }
                if (i == 2) {
                    // this also has lead to only half of the collisions being detected.
                    // if (distance <= 0) {
                    if (distance <= -1.0) {
                        break;
                    }
                    return true;
                }
            }
        }
    }
    
    return gotAnyCollision;
}