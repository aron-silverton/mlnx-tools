%global flavor vos

Summary: RDMA userland tools and scripts (Oracle VOS)
Name: oracle-rdma-tools
Version: 0.6.0
Release: 1%{?dist}%{?flavor}
License: GPLv2
Url: https://github.com/aron-silverton/mlnx-tools
Group: Applications/System
Source: https://github.com/aron-silverton/mlnx-tools/releases/download/v%{version}/%{name}-%{version}.tgz
BuildRoot: %{?build_root:%{build_root}}%{!?build_root:/var/tmp/%{name}}
Vendor: Oracle
Requires: perl
Requires: python
BuildRequires: python2

%description
Mellanox userland tools and scripts

For use on Oracle Linux systems running the Oracle Database Virtual OS
(VOS) layer.


%prep
%setup -n %{name}-%{version}

%install

add_env()
{
	efile=$1
	evar=$2
	epath=$3

cat >> $efile << EOF
if ! echo \$${evar} | grep -q $epath ; then
	export $evar=$epath:\$$evar
fi

EOF
}

touch mlnx-tools-files
cd ofed_scripts/utils
mlnx_python_sitelib=%{python_sitelib}
if [ "$(echo %{_prefix} | sed -e 's@/@@g')" != "usr" ]; then
	mlnx_python_sitelib=$(echo %{python_sitelib} | sed -e 's@/usr@%{_prefix}@')
fi
python setup.py install -O1 --prefix=%{buildroot}%{_prefix} --install-lib=%{buildroot}${mlnx_python_sitelib}
cd -

install -D -m 0755 ofed_scripts/cma_roce_mode %{buildroot}%{_sbindir}/cma_roce_mode
install -D -m 0755 ofed_scripts/ibdev2netdev %{buildroot}%{_bindir}/ibdev2netdev
install -D -m 0755 ofed_scripts/show_gids %{buildroot}%{_sbindir}/show_gids
install -D -m 0755 oracle/roce_config.sh %{buildroot}%{_bindir}/roce_config
install -D -m 0755 oracle/roce_config_persistent.sh %{buildroot}%{_bindir}/roce_config_persistent
install -D -m 0755 oracle/ifup-local %{buildroot}%{_sbindir}/ifup-local

if [ "$(echo %{_prefix} | sed -e 's@/@@g')" != "usr" ]; then
	conf_env=/etc/profile.d/mlnx-tools.sh
	install -d %{buildroot}/etc/profile.d
	add_env %{buildroot}$conf_env PYTHONPATH $mlnx_python_sitelib
	add_env %{buildroot}$conf_env PATH %{_bindir}
	add_env %{buildroot}$conf_env PATH %{_sbindir}
	echo $conf_env >> mlnx-tools-files
fi
find %{buildroot}${mlnx_python_sitelib} -type f -print | sed -e 's@%{buildroot}@@' >> mlnx-tools-files

%clean
rm -rf %{buildroot}

%files -f mlnx-tools-files
%defattr(-,root,root,-)
%{_sbindir}/*
%{_bindir}/*

%changelog
* Mon Aug 27 2018 Aron Silverton <aron.silverton@oracle.com> - 0:0.6.0
- Add "vos" to RPM release number (Aron Silverton) [Orabug 28550856]

* Mon Jul 09 2018 Aron Silverton <aron.silverton@oracle.com> - 0.6.0-1
- Add COPYING file for OpenIB.org BSD/GPLv2 (Aron Silverton)
- Add UPL copyright notice to Oracle source (Aron Silverton)
- Add COPYING files for individual licenses: UPL, OpenIB/BSD, GPLv2 (Aron Silverton)
- mlnx_qos: Add dcbnl enhancments cleanup code (Parav Pandit) [Orabug: 28314239]
- roce_config: Configure PFC using mlnx_qos (Avinash Repaka) [Orabug: 28194198]

* Tue Jun 12 2018 Aron Silverton <aron.silverton@oracle.com> - 0.5.8-2
- Add Oracle build environment and rename spec file

* Tue May 22 2018 Aron Silverton <aron.silverton@oraclecom> - 0.5.8-1
- Change name to "oracle-rdma-tools" and adjust version

* Thu Apr 05 2018 Aron Silverton <aron.silverton@oracle.com>
- Trigger roce_config on ifup/ifdown (Aron Silverton) [Orabug: 26364780]

* Wed Apr 04 2018 Aron Silverton <aron.silverton@oracle.com>
- Move Oracle files to /oracle (Aron Silverton) [Orabug: 27812014]
- Fix bad email address in changelog

* Tue Dec 19 2017 Aron Silverton <aron.silverton@oracle.com> - 1.5.4-0
- [Orabug: 27284449] Add Oracle copyright and remove Mellanox copyright
- [Orabug: 27284461] Remove obsolete installation script
- [Orabug: 27290597] Add OS distribution to generated package name
- [Orabug: 27290626] Add Python build dependency
- [Orabug: 27290690] Include roce_config_persistent in the RPM

* Wed Nov 1 2017 Vladimir Sokolovsky <vlad@mellanox.com>
- Initial packaging

