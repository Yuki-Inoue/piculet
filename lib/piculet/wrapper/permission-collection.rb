module Piculet
  class EC2Wrapper
    class SecurityGroupCollection
      class SecurityGroup
        class PermissionCollection
          include Logger::ClientHelper

          def initialize(security_group, direction, options)
            @security_group = security_group
            @permissions = security_group.send("#{direction}_ip_permissions")
            @direction = direction
            @options = options
          end

          def each
            perm_list = @permissions ? @permissions.aggregate : []

            perm_list.each do |perm|
              yield(Permission.new(perm, self, @options))
            end
          end

          def authorize(protocol, ports, sources, opts = {})
            log(:info, "  authorize #{format_sources(sources)}", opts.fetch(:log_color, :green))

            unless @options.dry_run
              sources = normalize_sources(sources)

              case @direction
              when :ingress
                @security_group.authorize_ingress(protocol, ports, *sources)
                @options.updated = true
              when :egress
                sources.push(:protocol => protocol, :ports => ports)
                @security_group.authorize_egress(*sources)
                @options.updated = true
              end
            end
          end

          def revoke(protocol, ports, sources, opts = {})
            log(:info, "  revoke #{format_sources(sources)}", opts.fetch(:log_color, :green))

            unless @options.dry_run
              sources = normalize_sources(sources)

              case @direction
              when :ingress
                @security_group.revoke_ingress(protocol, ports, *sources)
                @options.updated = true
              when :egress
                sources.push(:protocol => protocol, :ports => ports)
                @security_group.revoke_egress(*sources)
                @options.updated = true
              end
            end
          end

          def create(protocol, port_range, dsl)
            dsl_ip_ranges = dsl.ip_ranges || []
            dsl_groups = (dsl.groups || []).map do |i|
              i.kind_of?(Array) ? i : [@options.ec2.owner_id, i]
            end

            sources = dsl_ip_ranges + dsl_groups

            unless sources.empty?
              log(:info, 'Create Permission', :cyan, "#{log_id} > #{protocol} #{port_range}")
              authorize(protocol, port_range, sources, :log_color => :cyan)
            end
          end

          def log_id
            vpc = @security_group.vpc_id || :classic
            name = @security_group.name

            if @security_group.owner_id and not @options.ec2.own?(@security_group.owner_id)
              name = "#{@security_group.owner_id}/#{name}"
            end

            "#{vpc} > #{name}(#{@direction})"
          end

          private
          def normalize_sources(sources)
            normalized = []

            sources.each do |src|
              case src
              when String
                normalized << src
              when Array
                owner_id, group = src

                if src.any? {|i| AWS::EC2::SecurityGroup.elb?(i) }
                  normalized << {
                    :user_id    => AWS::EC2::SecurityGroup::ELB_OWNER,
                    :group_name => AWS::EC2::SecurityGroup::ELB_NAME
                  }
                else
                  unless group =~ /\Asg-[0-9a-f]+\Z/
                    sg_coll = @options.ec2.security_groups.filter('group-name', group)

                    if @options.ec2.own?(owner_id, @options)
                      sg_coll = sg_coll.filter('vpc-id', @security_group.vpc_id) if @security_group.vpc?
                    else
                      sg_coll = sg_coll.filter('owner-id', owner_id)
                    end

                    unless (sg = sg_coll.first)
                      raise "Can't find SecurityGroup: #{owner_id}/#{group} in #{@security_group.vpc_id || :classic}"
                    end

                    group = sg.id
                  end

                  normalized << {:user_id => owner_id, :group_id => group}
                end
              end
            end

            return normalized
          end

          def format_sources(sources)
            sources.map {|src|
              if src.kind_of?(Array)
                owner_id, group = src
                dst = [group]
                dst.unshift(owner_id) unless @options.ec2.own?(owner_id)
                dst.join('/')
              else
                src
              end
            }.join(', ')
          end
        end # PermissionCollection
      end # SecurityGroup
    end # SecurityGroupCollection
  end # EC2Wrapper
end # Piculet
