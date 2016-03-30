from __future__ import absolute_import, division, print_function, unicode_literals

import datetime as dt
import logging

logger = logging.getLogger(__name__)


from ..abstract import AbstractTextReader
from ...profile.dicts import Dicts


class DigibarS(AbstractTextReader):
    """Digibar S reader -> SVP style

    Info: http://www.odomhydrographic.com/product/digibar-s/
    """

    def __init__(self):
        super(DigibarS, self).__init__()
        self._ext.add('csv')

    def read(self, data_path):
        logger.debug('*** %s ***: start' % self.driver)

        self.init_data()  # create a new empty profile

        # initialize probe/sensor type
        self.ssp.meta.sensor_type = Dicts.sensor_types['SVP']
        self.ssp.meta.probe_type = Dicts.probe_types['SVP']

        self._read(data_path=data_path)
        self._parse_header()
        self._parse_body()

        logger.debug('*** %s ***: done' % self.driver)
        return True

    def _parse_header(self):
        """"Parsing header: time"""
        logger.debug('parsing header')

        if not self.ssp.meta.original_path:
            self.ssp.meta.original_path = self.fid.path

        # initialize data sample structures
        self.ssp.init_data(len(self.lines))

    def _parse_body(self):
        """Parsing samples: depth, speed, temp (+ profile time)"""
        logger.debug('parsing body')

        has_time = False
        has_date = False

        count = 0
        for line in self.lines[self.samples_offset:len(self.lines)]:

            # skip empty lines
            if not line:
                continue

            # first required data fields
            try:
                # 7-30-13, 8:57:31, 1503.50, 0.80, 16.40, 4.10
                date, time, speed, depth, temp, other = line.split(",")

                if speed == 0.0:
                    logger.info("skipping 0-speed row #%s" % (self.lines_offset + count))
                    count += 1
                    continue

                if not has_date:
                    try:
                        month, day, year = [int(i) for i in date.split('-')]
                        self.ssp.meta.utc_time = dt.datetime(day=day, month=month, year=year)
                        has_date = True
                    except Exception as e:
                        logger.info("unable to read date at row #%s" % (self.lines_offset + count))
                if not has_time:
                    try:
                        hour, minute, second = [int(i) for i in time.split(':')]
                        self.ssp.meta.utc_time += dt.timedelta(days=0, seconds=second, microseconds=0,
                                                               milliseconds=0, minutes=minute, hours=hour)
                        has_time = True
                    except Exception as e:
                        logger.info("unable to read time at row #%s" % (self.lines_offset + count))

                self.ssp.data.depth[count] = depth
                self.ssp.data.speed[count] = speed
                self.ssp.data.temp[count] = temp

            except ValueError:
                logger.warning("invalid conversion parsing of line #%s" % (self.samples_offset + count))
                continue
            except IndexError:
                logger.warning("invalid index parsing of line #%s" % (self.samples_offset + count))
                continue

            count += 1

        self.ssp.resize(count)