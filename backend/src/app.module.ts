/* eslint-disable prettier/prettier */
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { UserInventoryModule } from './user-inventory/user-inventory.module';
import appConfig from 'config/app.config';
import databaseConfig from 'config/database.config';
import { PuzzleCategoryModule } from './puzzle-category/puzzle-category.module';
import { RewardsModule } from './rewards/rewards.module';
import { PuzzleModule } from './puzzle/puzzle.module';
import { PuzzleSubmissionModule } from './puzzle-submission/puzzle-submission.module';
import { UserReportCardModule } from './user-report-card/user-report-card.module';
import { PuzzleDependencyModule } from './puzzle-dependency/puzzle-dependency.module';
import { TimeTrialModule } from './time-trial/time-trial.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env'],
      load: [appConfig, databaseConfig],
      cache: true,
    }),
    TypeOrmModule.forRootAsync({
      //end
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        host: configService.get('database.host'),
        port: +configService.get('database.port'),
        username: configService.get('database.user'),
        password: configService.get('database.password'),
        database: configService.get('database.name'),
        blog: configService.get('database.blog'),
        synchronize: configService.get('database.synchronize'),
        autoLoadEntities: configService.get('database.autoload'),
      }),
    }),
    AuthModule,
    UserInventoryModule,
    PuzzleCategoryModule,
    RewardsModule,
    PuzzleModule,
    PuzzleSubmissionModule,
    ContentModule,
    UserReportCardModule,
    PuzzleDependencyModule,
    TimeTrialModule,
  ],
  controllers: [AppController],
  providers: [
    
    AppService,
    
  ],
})
export class AppModule {}