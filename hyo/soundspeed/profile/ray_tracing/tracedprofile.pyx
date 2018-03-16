cimport numpy
import numpy
import math
from cpython cimport datetime
import logging

logger = logging.getLogger(__name__)

from hyo.soundspeed.profile.dicts import Dicts


cdef class TracedProfile:

    cpdef public double avg_depth
    cpdef public double half_swath
    cpdef public list rays
    cpdef public datetime.datetime date_time
    cpdef public double latitude
    cpdef public double longitude
    cpdef public list data

    def __init__(self, ssp, double half_swath=70, double avg_depth=10000, tss_depth=None, tss_value=None):
        # PyDateTime_IMPORT
        self.avg_depth = avg_depth
        self.half_swath = half_swath

        # select samples for the ray tracing (must be deeper than the transducer depth)
        depth = list()
        if tss_depth is not None:
            depth.append(tss_depth)
        speed = list()
        if tss_value is not None:
            speed.append(tss_value)

        vi = ssp.proc_valid

        for z_idx in range(0, len(ssp.proc.depth[vi])):

            # skip samples at depth less than the draft
            if tss_depth is not None:
                if ssp.proc.depth[vi][z_idx] <= tss_depth:
                    # logger.debug("skipping sample at depth: %.1f" % ssp.proc.depth[z_idx])
                    continue

            depth.append(ssp.proc.depth[vi][z_idx])
            speed.append(ssp.proc.speed[vi][z_idx])

            # stop after the first sample deeper than the avg depth (safer)
            if ssp.proc.depth[vi][z_idx] > self.avg_depth:
                break

        # remove extension value (if any)
        if (depth[-1] - depth[-2]) > 1000:
            logger.info("removed latest extension depth: %s" % depth[-1])
            del depth[-1]

        logger.debug("samples: %d" % len(depth))
        logger.debug("max depth: %f" % depth[-1])
        # logger.debug("depths: %s" % depth)
        # logger.debug("speeds: %s" % speed)

        # ray-trace a few angles (ref: Lurton, An Introduction to UA, p.50-52)
        txz_values = list()
        for angle in numpy.arange(0, int(math.ceil(self.half_swath + 1))):

            # ray angles
            beta = list()
            beta.append(math.radians(90.0 - angle))
            total_z = list()
            total_z.append(depth[0])
            total_x = list()
            total_x.append(0)
            total_t = list()  # total travel time
            total_t.append(0)

            # logger.debug("angle %d: beta0 %s" % (angle, math.degrees(beta[0])))

            for idx in range(len(depth) - 1):

                # calculate delta (next - current)
                dz = depth[idx+1] - depth[idx]
                dc = speed[idx+1] - speed[idx]
                # logger.debug("%s: dy %s, dc %s" % (x, dy, dc))

                if dc == 0:  # "constant speed" case: no curvature

                    if dz == 0:  # if (dc == 0) and (dy == 0):

                        logger.warning("skipping duplicated point: #%d" % idx)
                        continue

                    # gradient = dc/dy
                    beta.append(beta[idx])  # beta does not change
                    dx = dz / (math.tan(beta[idx+1]))  # no curvature!
                    dt = (((dx**2)+(dz**2))**.5) / speed[idx+1]

                elif dz == 0:  # "same depth" case: just adjust the ray angle

                    beta.append(math.acos((speed[idx + 1] / speed[idx]) * (math.cos(beta[idx]))))
                    continue

                else:  # if (dc != 0) and (dz != 0):

                    gradient = dc / dz  # Lurton, (2.64)
                    if math.cos(beta[idx]) == 0:
                        curve = 0
                    else:  # if math.cos(beta[x]) != 0:
                        curve = speed[idx] / (gradient * math.cos(beta[idx]))  # Lurton, (2.66)

                    beta_cos = speed[idx + 1] * (math.cos(beta[idx])) / speed[idx]
                    if beta_cos > 1.0:
                        logger.warning("angle %d, sample %d -> invalid beta cos: %s" %
                                       (angle, idx, beta_cos))
                        beta_cos = 1.0
                    if beta_cos < -1.0:
                        logger.warning("angle %d, sample %d -> invalid beta cos: %s" %
                                       (angle, idx, beta_cos))
                        beta_cos = -1.0

                    beta.append(math.acos(beta_cos))  # Derived from Lurton, (2.65)

                    dx = curve * ((math.sin(beta[idx])) - (math.sin(beta[idx + 1])))  # Lurton, (2.67)
                    dt = abs((1 / gradient) *
                             math.log(
                                (speed[idx + 1] / speed[idx]) *
                                (abs((1 + math.sin(beta[idx])) / (1 + math.sin(beta[idx + 1]))))))  # Lurton, (2.70)

                total_z.append(total_z[-1] + dz)
                total_x.append(total_x[-1] + dx)
                total_t.append(total_t[-1] + dt)

            interp_t = numpy.linspace(total_t[0], total_t[-1], num=20)
            # logger.info("interp_t:\n%s" % interp_t)
            interp_x = numpy.interp(interp_t, total_t, total_x)
            interp_z = numpy.interp(interp_t, total_t, total_z)
            txz_values.append(numpy.array([interp_t, interp_x, interp_z]))

        self.rays = txz_values
        logger.debug("ray samples: %d" % len(self.rays[0][0]))
        self.date_time = ssp.meta.utc_time
        self.latitude = ssp.meta.latitude
        self.longitude = ssp.meta.longitude
        self.data = [depth, speed]

    def __repr__(self):
        msg = "<%s>\n" % self.__class__.__name__

        msg += "  <timestamp: %s>\n" % self.date_time
        msg += "  <latitude: %.7f>\n" % self.latitude
        msg += "  <longitude: %.7f>\n" % self.longitude
        msg += "  <avg depth: %.3f>\n" % self.avg_depth
        msg += "  <half swatch: %.1f>\n" % self.half_swath
        msg += "  <rays: %d>\n" % len(self.rays)
        msg += "  <samples: %d>" % len(self.data[0])

        return msg